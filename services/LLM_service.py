from db.database import get_db_connection
import time
import json
import jsonlines
import io
from openai import OpenAI
import textwrap
from API_KEYs import LM_API_KEY

BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
PROMPT = textwrap.dedent("""\
你是一名专业学术助理，请**严格基于以下摘要原文**生成**中文**解释。**禁止任何外部知识、推断或数据补充**。

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

## 输出格式（严格遵循JSON格式,内容通过**中文**回答）
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

    def get_abstracts(self):
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, abstract, editor_summary, structured_abstract FROM articles WHERE llm_summary IS NULL")
            rows = cursor.fetchall()
            ids = [row['id'] for row in rows]
            abstracts = [
                " ".join(filter(None, [
                    f"abstract: {row['abstract']}" if row['abstract'] else None,
                    f"editor_summary: {row['editor_summary']}" if row['editor_summary'] else None,
                    f"structured_abstract: {row['structured_abstract']}" if row['structured_abstract'] else None
                ])) for row in rows
            ]
            return abstracts, ids

    def build_batch(self, abstracts, ids):
        jsons = []
        for i, abstract in enumerate(abstracts[0:1]):
            entry = {
                "custom_id": f"{ids[i]}",
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

        # 将列表转换为换行符分隔的字符串，并转换为字节流
        jsonl_content = "\n".join(jsons).encode("utf-8")
        file_io = io.BytesIO(jsonl_content)

        return file_io

    def generate_summary(self, batch_file):
        file_id = self.app.files.create(
            file=("batch_input.jsonl", batch_file),
            purpose="batch"
        ).id

        batch_id = self.app.batches.create(
            input_file_id=file_id,
            endpoint="/v1/chat/completions",
            completion_window="24h"
        ).id

        result_id = None
        while True:
            time.sleep(60)
            batch = self.app.batches.retrieve(batch_id)
            if batch.status == "completed":
                result_id = batch.output_file_id
                print(result_id)
                break
            elif batch.status == "in_progress":
                print("Batch is still processing...")
                continue
            elif batch.status == "failed":
                result_id = batch.error_file_id
                raise Exception("Batch processing failed")

        res_jsonl = self.app.files.content(result_id).text

        return res_jsonl
    

    def process_results(self, res_jsonl):
        summaries = []
        result_ids = []
        with jsonlines.Reader(io.StringIO(res_jsonl)) as reader:
            for data in reader:
                custom_id = data.get("custom_id")
                content = data.get("response", {}).get("body", {}).get("choices", [{}])[0].get("message", {}).get("content")
                if content and custom_id:
                    summaries.append(content)
                    result_ids.append(custom_id)
        self.update_summaries(summaries, result_ids)


    def update_summaries(self, summaries, ids):
        with get_db_connection() as conn:
            cursor = conn.cursor()
            for i, summary in enumerate(summaries):
                cursor.execute(
                    "UPDATE articles SET llm_summary = ?, processed_at = CURRENT_TIMESTAMP, status = 'processed' WHERE id = ?",
                    (summary, ids[i])
                )
            conn.commit()

if __name__ == "__main__":
    service = LLMService()
    # abstracts, ids = service.get_abstracts()
    # batch_file = service.build_batch(abstracts, ids)
    # service.generate_summary(batch_file)
    result = service.process_results(
        """
{"id":"e3fa01b1-fe73-4ab9-9bce-915fcf966797","custom_id":"2435","response":{"status_code":200,"request_id":"e3fa01b1-fe73-4ab9-9bce-915fcf966797","body":{"created":1768117193,"usage":{"completion_tokens":642,"prompt_tokens":1004,"total_tokens":1646},"model":"qwen-plus","id":"chatcmpl-e3fa01b1-fe73-4ab9-9bce-915fcf966797","choices":[{"finish_reason":"stop","index":0,"message":{"role":"assistant","content":"{\n    \"title\": \"脂质转移蛋白-脂质复合物的系统性表征及其功能影响\",\n    \"summary\": \"脂质转移蛋白（LTPs）维持细胞器膜的特异性脂质组成。在人类中，许多LTPs与疾病相关，但大多数LTPs的转运底物及辅助脂质尚不清楚。通过结合生化、脂质组学和计算方法，系统性地表征了LTP-脂质复合物，并测量了LTP功能获得对细胞脂质组的影响。在分析的约一百种LTPs中，确定了其中近一半所结合的脂质，验证了已知配体并发现了多个新配体，涵盖大多数LTP家族。LTP功能增强影响了其已知和新发现脂质配体在细胞中的丰度，表明这两类配体具有相当的功能重要性。通过结构生物信息学分析，揭示了脂质选择性的机制，识别出基于头部基团或酰基链的偏好。研究展示了LTP动员其配体的一些基本原理：它们通常与多个脂质类别相互作用，表现出广泛但具有选择性的偏好，不仅针对特定头部基团，还倾向于酰基链较短且含有一或两个不饱和键的脂质种类，提示只有部分脂质物种能被有效动员。该数据集可作为不同细胞类型和状态（如病理状态）下进一步分析的资源。\",\n    \"highlights\": \"解决了**医学**中脂质转移蛋白功能与疾病关联机制不明确的问题，为理解病理状态下脂质代谢紊乱提供基础数据支持\",\n    \"innovations\": [\n        \"结合生化、脂质组学和计算方法系统性表征LTP-脂质 complexes：我们结合了生化、脂质组学和计算方法来系统性地表征LTP-脂质复合物\",\n        \"确定了约一半被分析LTPs的结合脂质并发现新配体：我们识别了约一百种LTPs中近一半的结合脂质，确认已知配体的同时发现了新配体\",\n        \"揭示LTP功能获得对细胞脂质组中已知与新配体丰度的影响：增益功能影响了已知和新鉴定脂质配体的细胞丰度，表明二者具有相当的功能相关性\",\n        \"通过结构生物信息学解析脂质选择性机制：使用结构生物信息学方法，鉴定了基于头部基团或酰基链的脂质选择性偏好\",\n        \"提出LTP动员脂质的基本原则：展示了LTP如何动员配体的基本原理，包括对短链及单双不饱和脂质的偏好\"\n    ],\n    \"maintag\": \"医学\",\n    \"subtags\": [\n        \"脂质转移蛋白 LTPs\",\n        \"脂质组学 lipidomics\",\n        \"结构生物信息学 structural bioinformatics\",\n        \"酰基链 acyl chain\",\n        \"脂质选择性 lipid selectivity\"\n    ]\n}"}}],"object":"chat.completion"}},"error":null}
{"id":"b6706adc-d954-4dd6-84b7-c3f9a75e01e0","custom_id":"2434","response":{"status_code":200,"request_id":"b6706adc-d954-4dd6-84b7-c3f9a75e01e0","body":{"created":1768117190,"usage":{"completion_tokens":483,"prompt_tokens":971,"total_tokens":1454},"model":"qwen-plus","id":"chatcmpl-b6706adc-d954-4dd6-84b7-c3f9a75e01e0","choices":[{"finish_reason":"stop","index":0,"message":{"role":"assistant","content":"{\n    \"title\": \"电化学驱动的Matteson同系化反应新方法\",\n    \"summary\": \"Matteson同系化反应自1980年发展以来，通过向C−B键插入实现碳链延长，传统方法需经三步：碳负离子形成、对有机硼化合物的亲核加成以及热或路易斯酸促进的硼酸酯重排，通常需严格条件如低温及对空气和水分敏感试剂的操作。本研究报道了一种将上述三步整合为一锅法电化学过程的Matteson型同系化反应。该概念验证方法结合了电还原脱氟与硼酸酯重排，无需使用有机锂试剂、低温条件或专用设备。首次采用易得的三氟甲基芳烃作为卡宾前体，拓展了Matteson反应的应用范围。通过鉴定关键中间体、DFT计算和电化学分析等系统机理研究，证实了硼酸酯形成与重排在这一“e-Matteson”同系化反应中的作用。\",\n    \"highlights\": \"解决了**化学**中传统Matteson反应操作复杂、条件苛刻的问题，为有机合成提供了一种无需强碱、低温或敏感试剂的简化流程\",\n    \"innovations\": [\n        \"• 开发了一锅法电化学流程：将传统Matteson反应的三步整合为单一电化学过程（原文：integrates these three transformations into a one-pot electrochemical process）\",\n        \"• 首次使用三氟甲基芳烃作为卡宾前体：采用易得的三氟甲基芳烃替代传统碳负离子源（原文：trifluoromethylarenes are employed as carbenoid precursors for the first time）\",\n        \"• 实现无有机锂试剂与非低温条件下的反应：通过电还原脱氟避免使用有机锂试剂和低温（原文：eliminating the need for organolithium reagents, cryogenic conditions, or specialist setups）\"\n    ],\n    \"maintag\": \"化学\",\n    \"subtags\": [\n        \"Matteson同系化反应\",\n        \"电化学合成\",\n        \"硼酸酯重排\",\n        \"脱氟反应\",\n        \"DFT计算\"\n    ]\n}"}}],"object":"chat.completion"}},"error":null}
"""
    )
    print(result)