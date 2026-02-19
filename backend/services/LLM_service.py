import logging
from db.article_db import ArticleRepository
import time
import json
import jsonlines
import io
from openai import OpenAI
import textwrap
from API_KEYs import LM_API_KEY

logger = logging.getLogger(__name__)

BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
PROMPT = textwrap.dedent("""\
你是一名专业学术助理，请**严格基于以下摘要原文**生成**中文**解释。**禁止任何外部知识、推断或数据补充**。
                         
**0. 标题**  
用中文拟定标题，**必须包含摘要中出现的核心技术/发现**

**1. 内容精炼**  
- 详细复述并解释摘要中的 **事实性陈述**（问题/方法/结果）  
- **禁止添加**：  
    × "本文" "本研究" "首次" "突破性" "显著优于" 等冗余或主观表述  
    × 未在摘要中出现的**具体数字**（如摘要写"效率提升"，但未写"15%"，则不可补充数字）  
- 技术名词保留原文并标注中文（例：Transformer 模型 → Transformer 模型（一种深度学习架构））

**2. 意义阐述**  
- **当摘要明确提及应用价值时**，按此模板：  
    > 解决了[**学科领域**]中[具体问题]，为[应用场景]提供[**摘要原文中的量化效果**]  

**3. 创新点提取**  
- **每条创新点必须包含摘要原文的直接证据**，格式：  
    • [创新动作]：[**摘要原句或精确转述**]（例："开发了X技术" → 摘要中需有"we developed X"）  
- **禁止生成**：  
    × 任何**对比性结论**（如"较传统方法提升XX%"，除非摘要明确写出对比数据）  
    × "首次""新"等未在摘要中出现的修饰词  
- 若摘要无明确创新描述，输出：  
    > 摘要未明确说明创新点  

**4. 领域标记**  
- **主标签（必选）**：从以下**学科领域**中选 **1 个**：  
    **计算机 · 生物 · 医学 · 化学 · 材料 · 环境 · 物理 · 工程 · 农业 · 经济 · 心理学**  
    → 选择依据：摘要中**核心问题所属的学科**（例：摘要研究"水稻基因编辑" → 主标签=**生物**）  
- **子标签（可选）**：从摘要中提取 **1-5 个技术/方法关键词**（中英对照），例如：  
    `CRISPR基因编辑` `深度学习` `纳米材料` `气候模型`  
    → **禁止添加**摘要未提及的子标签

## 输出格式（严格遵循JSON格式,所有总结内容通过**中文**回答）
{
    "title":"<标题>",
    "summary":"<精炼摘要>",
    "highlights":"<价值阐述 或 "摘要未说明实际应用价值"> ",
    "innovations":["<创新点1>","<创新点2>"],
    "maintag":"<主标签>",
    "subtags":["子标签1","子标签2"]
}

## 违规示例（你必须避免）
主标签：`#人工智能`  
（**错误**：人工智能是技术，不是学科领域；正确主标签应为 **#计算机**）  

创新点："首次实现水稻基因编辑效率提升20%"  
（摘要原文："edited rice genes with improved efficiency" → **无"首次"，无"20%"**）
""")

class LLMService:
    def __init__(self):
        self.app = OpenAI(
            api_key=LM_API_KEY,
            base_url=BASE_URL
        )
        self.repo = ArticleRepository() # 注入依赖

    def run_submission_cycle(self, limit=None):
        """执行一次完整的提交周期"""
        # 1. 获取数据
        rows, ids = self.repo.get_pending_articles(limit=limit)
        if not ids:
            logger.info("No pending articles found.")
            return

        # 2. 构建数据 (这里可以保留 filter/join 逻辑)
        abstracts = self._format_abstracts(rows) 
        batch_file = self._build_batch_file(abstracts, ids)

        # 3. 提交任务
        batch_id = self._submit_to_api(batch_file)
        
        # 4. 更新状态
        self.repo.mark_articles_as_submitted(ids, batch_id)
        logger.info(f"Submitted batch {batch_id}")

    def run_update_cycle(self):
        """执行一次完整的检查更新周期"""
        active_batches = self.repo.get_active_batch_ids()
        for batch_id in active_batches:
            results = self._fetch_results_from_api(batch_id)
            if results:
                # 解析并更新
                updates = self._parse_results(results) # 返回 [(summary, 'processed', id), ...]
                self.repo.update_article_summaries(updates)
                logger.info(f"Batch {batch_id} processed.")

    def _format_abstracts(self, rows):
        """格式化摘要数据为 API 所需的结构"""
        return [
            " ".join(filter(None, [
                f"abstract: {row['abstract']}" if row['abstract'] else None,
                f"editor_summary: {row['editor_summary']}" if row['editor_summary'] else None,
                f"structured_abstract: {row['structured_abstract']}" if row['structured_abstract'] else None
            ])) for row in rows
        ]

    def _build_batch_file(self, abstracts, ids):
        """构建批处理文件内容"""
        jsons = []
        for i, abstract in enumerate(abstracts):
            entry = {
                "custom_id": f"{ids[i]}", # 使用内部 ids
                "method": "POST",
                "url": "/v1/chat/completions",
                "body": {
                    "model": "qwen-plus",
                    "messages": [
                        {"role": "system", "content": PROMPT},
                        {"role": "user", "content": abstract}
                    ],
                    "response_format":{"type": "json_object"},
                    "temperature": 0.25,
                    "top_p": 0.7
                }
            }
            jsons.append(json.dumps(entry, ensure_ascii=False))
        logger.info(f"Built batch file with {len(jsons)} entries.")
        jsonl_content = "\n".join(jsons).encode("utf-8")
        return io.BytesIO(jsonl_content)

    def _submit_to_api(self, batch_file):
        """提交批处理任务并记录 ID"""
        file_info = self.app.files.create(file=("batch_input.jsonl", batch_file), purpose="batch")
        batch_job = self.app.batches.create(
            input_file_id=file_info.id,
            endpoint="/v1/chat/completions",
            completion_window="24h"
        )
        
        return batch_job.id
    
    def _fetch_results_from_api(self, batch_id):
        """从 API 获取批处理结果"""
        batch = self.app.batches.retrieve(batch_id)
        if batch.status == "completed":
            if batch.output_file_id:
                return self.app.files.content(batch.output_file_id).text
            else:
                logger.error(f"Batch {batch_id} status is 'completed' but output_file_id is None. Clearing status for retry.")
                self.repo.clear_batch_llm_status(batch_id)
                return None
        elif batch.status in ["failed", "expired", "cancelled"]:
            self.repo.clear_batch_llm_status(batch_id)
            raise Exception(f"Batch {batch_id} ended with status: {batch.status}")
        return None # 仍在处理中

    def _parse_results(self, res_jsonl):
        """解析 API 返回的结果"""
        summaries = []
        result_ids = []
        with jsonlines.Reader(io.StringIO(res_jsonl.strip())) as reader:
            for data in reader:
                custom_id = data.get("custom_id")
                content_raw = data.get("response", {}).get("body", {}).get("choices", [{}])[0].get("message", {}).get("content")
                
                if content_raw and custom_id:
                    try:
                        # 解析内层 JSON 字符串为 Python 字典
                        parsed_content = json.loads(content_raw, strict=False)
                        clean_content = json.dumps(parsed_content, ensure_ascii=False)
                        
                        summaries.append(clean_content)
                        result_ids.append(custom_id)
                    except json.JSONDecodeError as e:
                        logger.error(f"解析摘要 JSON 内容失败 (ID: {custom_id}): {e}")
                        summaries.append(content_raw)
                        result_ids.append(custom_id)

        # 返回 [(summary, 'processed', id), ...]
        return [(summaries[i], "processed", result_ids[i]) for i in range(len(result_ids))]

if __name__ == "__main__":
    service = LLMService()
    logger.info("Looking for new articles to process...")
    service.run_submission_cycle(limit=100)
    while True:
        logger.info("Checking for existing active tasks...")
        service.run_update_cycle()
        time.sleep(60)