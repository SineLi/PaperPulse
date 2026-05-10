import os
import logging
from db.article_db import ArticleRepository
import time
import json
import jsonlines
import io
from openai import OpenAI
import textwrap
from utils.logging_utils import log_event

logger = logging.getLogger(__name__)

BASE_URL = os.getenv("LLM_BASE_URL")
LM_API_KEY = os.getenv("LM_API_KEY")
LLM_HTTP_TIMEOUT_SECS = float(os.getenv("LLM_HTTP_TIMEOUT_SECS", "120"))
DEFAULT_SUBMISSION_LIMIT = int(os.getenv("LLM_SUBMISSION_LIMIT", "-1"))
LLM_BATCH_WARN_AFTER_SECS = 2 * 60
PROMPT = textwrap.dedent("""\
你是一名专业学术助理，请基于以下摘要原文生成**中文**解释。
**核心原则**：
1. **事实忠诚**：事实性内容（方法/结果/数据）必须严格忠于原文，严禁捏造。
2. **背景常识**：背景性内容允许使用公认的领域常识进行补充，但严禁捏造具体事件。
3. **类型适配**：自动识别文章类型（研究论文/综述文章），调整总结侧重（研究论文侧重方法结果，综述文章侧重覆盖范围与洞察）。

**0. 标题**  
用中文拟定标题，以**概括整篇工作的主要目标或贡献**为主，适度加入少量有吸引力的表述，但不得喧宾夺主。

- 标题应优先回答“这项工作整体在做什么”，而不是只描述某个局部技术细节或实验场景。
- 必须包含摘要中出现的至少 1 个核心技术 / 研究对象 / 关键概念（如方法名、模型名、材料、研究对象等），但不需要逐一罗列所有细节。
- 标题结构以“整体概括 + 轻微修饰”为主，推荐形式：
    - “利用 X 完成 Y 任务的整体方法框架”
    - “面向 Y 问题的 X 方法：在 Z 方面带来更高效 / 更准确的方案”
    - “用 X 改进 Y 过程的整体设计”
- 吸引人的表达应简短、克制，只用来点出亮点或优势，例如“更高效”“更节省资源”“更易部署”等，不使用夸张或宣传性词语（禁止“颠覆”“革命性”“黑科技”“秒杀”“最强”等）。
- 避免纯学术化标题模板，如：
    - “基于 X 的 Y 研究”
    - “X 方法在 Y 问题中的应用研究”
    若摘要原有标题属于此类模板，应在保持事实不变的前提下改写为更清晰体现整体工作的表述。
- 标题不应加入摘要中未出现的具体对比结论或数字（如“准确率提升 20%”“优于所有现有方法”等）。
- 建议长度在 18–30 个汉字之间，偏向完整概括，不强求极短标题。

**1. 一句话总结**  
- 用**一句话**概括该研究的核心内容或意义。
- **要求**：语言通俗易懂，让非相关专业人士也能理解大致方向。
- **限制**：必须基于摘要原文信息进行简化，**禁止**使用摘要未提及的类比、比喻或外部知识来解释概念。
- **综述适配**：若是综述，可表述为“本文综述了...领域的进展/挑战”。

**2. 研究背景（重点对象解释）**
- **目标**：用最少的外部知识帮助读者理解“本文围绕的核心对象/方案是什么、通常用来做什么”，其余仍以摘要原文为准。

【A. 重点对象解释（仅 1 个）】
- 先从摘要中识别“目标研究对象/核心方案”（只选 1 个）：
    - 优先级：摘要反复出现的核心名词；或与“提出/设计/研究/评估/综述”直接相关的对象。
    - 若存在多个候选，只选对理解全文最关键的那个；不要列清单。
- 对该对象给出 1–2 句通用解释（允许使用非输入知识），写法必须是“通常/一般/常见”的百科级定义：
    - 示例格式：“X通常指……，常用于……（不超过两句）”
- **允许的非输入知识范围（仅限）**：
  √ 该对象/方案的公认定义、基本用途、典型作用机制（常识级）
- **禁止**：
  × 把外部知识写成“本文做到了/证明了/优于/实现了”的论文事实
  × 引入摘要未提及的具体数据、对比对象、实验设置、应用落地场景
  × 引用具体论文/作者/年份（除非摘要明确出现）
- **不确定处理**：若摘要无法明确核心对象，输出：“摘要未明确给出可解释的核心研究对象”。

【B. 背景与痛点（常识 + 摘要）】
- 用 1–2 句说明该方向通常要解决的通用痛点（可用公认常识，避免具体事件/趋势/数字）。
- 再用 1 句把“本文要解决什么/目标是什么”落回摘要原文（每个要点都必须能在摘要中找到对应依据）。

**3. 内容精炼**  
- 详细复述并解释摘要中的 **核心陈述**。
- **研究论文侧重**：问题/方法/实验结果。
- **综述文章侧重**：综述范围/分类框架/核心洞察/未来方向。
- **禁止添加**：  
    × "本文" "本研究" "首次" "突破性" "显著优于" 等冗余或主观表述  
    × 未在摘要中出现的**具体数字**（如摘要写"效率提升"，但未写"15%"，则不可补充数字）
- 技术名词保留原文并标注中文（例：Transformer 模型 → Transformer 模型（一种深度学习架构））
- **严格性**：此部分**禁止使用外部知识**，必须完全基于摘要原文。

**4. 意义阐述**  
- **当摘要明确提及应用价值时**，按此模板：  
    > 解决了 [**学科领域**] 中 [具体问题]，为 [应用场景] 提供 [**摘要原文中的量化效果**]  
- **若是综述文章**，可按此模板：  
    > 提供了 [**学科领域**] 的系统性概述，指出了 [关键挑战/未来方向]，为 [研究人员/从业者] 提供 [参考/指导]  
- **若缺失处理**：若摘要未明确提及应用价值，输出："摘要未说明实际应用价值"

**5. 创新点提取**  
- **每条创新点必须包含摘要原文的直接证据**。
- **研究论文格式**：[创新动作]：[**摘要原句或精确转述**]（例："开发了 X 技术" → 摘要中需有"we developed X"）
- **综述文章格式**：[贡献类型]：[**摘要原句或精确转述**]（例："提出了新分类" → 摘要中需有"propose a new taxonomy"）
- **允许的创新点**：  
    × 具体方法改进（研究论文）  
    × 独特的分类视角/框架（综述）  
    × 全面的覆盖范围/时间跨度（综述）  
    × 明确指出的未来路线图（综述）
- **格式约束**：  
    × **纯文本输出**，禁止在开头添加 •、-、* 或 1. 等列表符号（JSON 数组已起到列表作用）。  
    × 禁止生成任何对比性结论（除非摘要明确写出对比数据）。  
    × 禁止使用"首次""新"等未在摘要中出现的修饰词。
- 若摘要无明确创新描述，输出：  
    > 摘要未明确说明创新点

**6. 领域标记**  
- **主标签（必选）**：**必须从以下列表中选择 1 个**，严禁自创标签。若遇细分领域，请映射到最接近的候选词。  
    **计算机 · 生物 · 医学 · 化学 · 材料 · 环境 · 物理 · 工程 · 农业 · 经济 · 心理学 · 数学 · 地球科学 · 能源 · 食品科学 · 药学 · 社会科学 · 人文 · 法学 · 教育学**  
    → **映射指南**：  
        - 食品/营养/发酵 → **食品科学** (若无则选 农业/生物)  
        - 电池/光伏/电力 → **能源** (若无则选 工程/化学)  
        - 药物研发/药理 → **药学** (若无则选 医学/化学)  
        - 社会/管理/政治 → **社会科学** (若无则选 经济/法学)  
        - 纯理论推导 → **数学**  
        - 地质/气象/海洋 → **地球科学**  
- **子标签（可选）**：从摘要中提取 **1-5 个技术/方法关键词**。  
    → **格式要求**：**优先使用中文，仅保留通用缩写**（如 DNA, AI, CNN），**禁止中英对照长翻译**。  
    → **示例**：`电化学合成` `深度学习` `纳米材料` `CRISPR`  
    → **禁止**：`电化学合成 Electrochemical synthesis` `深度学习 Deep Learning`  
    → **禁止添加**摘要未提及的子标签

## 输出格式（严格遵循 JSON 格式，所有总结内容通过**中文**回答）
{
    "title": "<标题>",
    "one_sentence_summary": "<一句话总结>",
    "background": "<研究背景（可含公认常识）或 '摘要未明确提及研究背景'>",
    "summary": "<内容精炼（严格基于原文）>",
    "highlights": "<价值阐述 或 '摘要未说明实际应用价值'>",
    "innovations": ["<创新点 1>", "<创新点 2>"],
    "maintag": "<主标签>",
    "subtags": ["子标签 1", "子标签 2"]
}

## 违规示例（你必须避免）
主标签：`#人工智能`  
（**错误**：人工智能是技术，不是学科领域；正确主标签应为 **#计算机**）  

主标签：`#食品`  
（**错误**：候选列表中无“食品”，应映射为 **#食品科学** 或 **#农业**；严禁自创列表外标签）  

子标签："电化学合成 Electrochemical synthesis"  
（**错误**：包含英文全称，冗长；**正确**："电化学合成"）  

创新点："• 开发了 X 技术"  
（**错误**：包含列表符号 •；**正确**："开发了 X 技术"）  

创新点："首次实现水稻基因编辑效率提升 20%"  
（摘要原文："edited rice genes with improved efficiency" → **无"首次"，无"20%"**）

研究背景："随着 2023 年生成式 AI 爆发，企业急需降低成本..."  
（**错误**：摘要未提及 2023 年或企业需求，属于编造具体事件；**正确**：应使用通用常识，如"深度学习模型通常面临较高的计算成本问题"）

内容精炼："使用了 BERT 模型，效果比 GPT-4 更好"  
（**错误**：摘要未提及 GPT-4，属于引入外部对比；**正确**：仅描述摘要中提到的对比对象或结果）

综述类错误："实验结果表明该方法准确率 95%"  
（**错误**：综述文章通常无具体实验数据，除非摘要明确提及 meta 分析数据；**正确**：应总结其覆盖的范围或提出的观点）
""")

class LLMService:
    def __init__(self):
        self.app = OpenAI(
            api_key=LM_API_KEY,
            base_url=BASE_URL,
            timeout=LLM_HTTP_TIMEOUT_SECS,
        )
        self.repo = ArticleRepository() # 注入依赖

    def run_submission_cycle(self, limit=None):
        """执行一次完整的提交周期"""
        # 1. 获取数据
        cycle_started_at = time.monotonic()
        effective_limit = limit if limit is not None else DEFAULT_SUBMISSION_LIMIT
        if effective_limit == -1:
            effective_limit = None
        rows, ids = self.repo.get_pending_articles(limit=effective_limit)
        if not ids:
            log_event(logger, logging.INFO, "llm_submission_skipped_no_pending_articles")
            return

        log_event(logger, logging.INFO, "llm_submission_started", article_count=len(ids), limit=effective_limit)

        # 2. 构建数据 (这里可以保留 filter/join 逻辑)
        abstracts = self._format_abstracts(rows) 
        batch_file = self._build_batch_file(abstracts, ids)

        # 3. 提交任务
        submit_started_at = time.monotonic()
        batch_id = self._submit_to_api(batch_file)
        submit_elapsed = time.monotonic() - submit_started_at
        log_event(
            logger,
            logging.WARNING if submit_elapsed >= LLM_BATCH_WARN_AFTER_SECS else logging.INFO,
            "llm_batch_submitted_to_provider",
            batch_id=batch_id,
            elapsed_secs=submit_elapsed,
            article_count=len(ids),
        )
        
        # 4. 更新状态
        self.repo.mark_articles_as_submitted(ids, batch_id)
        log_event(logger, logging.INFO, "llm_submission_completed", batch_id=batch_id, elapsed_secs=time.monotonic() - cycle_started_at)

    def run_update_cycle(self, timeout_secs=600):
        """执行一次完整的检查更新周期"""
        cycle_started_at = time.monotonic()
        active_batches = self.repo.get_active_batch_ids()
        log_event(logger, logging.INFO, "llm_update_started", active_batch_count=len(active_batches))
        for batch_id in active_batches:
            batch_started_at = time.monotonic()
            results = self._fetch_results_from_api(batch_id)
            if results:
                # 解析并更新
                updates = self._parse_results(results) # 返回 [(summary, 'processed', id), ...]
                self.repo.update_article_summaries(updates)
                log_event(logger, logging.INFO, "llm_batch_processed", batch_id=batch_id, update_count=len(updates))
            batch_elapsed = time.monotonic() - batch_started_at
            log_event(
                logger,
                logging.WARNING if batch_elapsed >= LLM_BATCH_WARN_AFTER_SECS else logging.INFO,
                "llm_batch_update_completed",
                batch_id=batch_id,
                elapsed_secs=batch_elapsed,
            )
            if time.monotonic() - cycle_started_at >= timeout_secs:
                log_event(logger, logging.WARNING, "llm_update_cycle_timeout", elapsed_secs=time.monotonic() - cycle_started_at)
                break
        log_event(logger, logging.INFO, "llm_update_completed", elapsed_secs=time.monotonic() - cycle_started_at)

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
        log_event(logger, logging.INFO, "llm_batch_file_built", entry_count=len(jsons))
        jsonl_content = "\n".join(jsons).encode("utf-8")
        return io.BytesIO(jsonl_content)

    def _submit_to_api(self, batch_file):
        """提交批处理任务并记录 ID"""
        file_info = self.app.files.create(file=("batch_input.jsonl", batch_file), purpose="batch")
        log_event(logger, logging.INFO, "llm_input_file_uploaded", file_id=file_info.id)
        batch_job = self.app.batches.create(
            input_file_id=file_info.id,
            endpoint="/v1/chat/completions",
            completion_window="24h"
        )
        log_event(logger, logging.INFO, "llm_batch_created", batch_id=batch_job.id, input_file_id=file_info.id)

        return batch_job.id
    
    def _fetch_results_from_api(self, batch_id):
        """从 API 获取批处理结果"""
        batch = self.app.batches.retrieve(batch_id)
        if batch.status == "completed":
            if batch.output_file_id:
                log_event(logger, logging.INFO, "llm_batch_result_download_started", batch_id=batch_id, output_file_id=batch.output_file_id)
                return self.app.files.content(batch.output_file_id).text
            else:
                log_event(logger, logging.ERROR, "llm_batch_completed_missing_output", batch_id=batch_id)
                self.repo.clear_batch_llm_status(batch_id)
                return None
        elif batch.status in ["failed", "expired", "cancelled"]:
            self.repo.clear_batch_llm_status(batch_id)
            log_event(logger, logging.ERROR, "llm_batch_terminal_error", batch_id=batch_id, status=batch.status)
            return None
        log_event(logger, logging.INFO, "llm_batch_still_running", batch_id=batch_id, status=batch.status)
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
                        log_event(logger, logging.DEBUG, "llm_result_parsed", article_id=custom_id, parsed_json=True)
                    except json.JSONDecodeError as e:
                        logger.exception("event=llm_result_parse_failed article_id=%s detail=%s", custom_id, e)
                        summaries.append(content_raw)
                        result_ids.append(custom_id)

        # 返回 [(summary, 'processed', id), ...]
        updates = [(summaries[i], "processed", result_ids[i]) for i in range(len(result_ids))]
        log_event(logger, logging.INFO, "llm_results_parsed", update_count=len(updates))
        return updates

if __name__ == "__main__":
    service = LLMService()
    logger.info("Looking for new articles to process...")
    service.run_submission_cycle(limit=100)
    while True:
        logger.info("Checking for existing active tasks...")
        service.run_update_cycle()
        time.sleep(60)
