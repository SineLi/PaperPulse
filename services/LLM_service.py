from db.database import get_db_connection
import time
import json
import io
from openai import OpenAI
from API_KEYs import LM_API_KEY

BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

class LLMService:
    def __init__(self):
        self.app = OpenAI(
            api_key=LM_API_KEY,
            base_url=BASE_URL
        )

    def get_abstracts(self):
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT abstract, editor_summary, structured_abstract FROM articles WHERE llm_summary IS NULL")
            rows = cursor.fetchall()
            abstracts = [
                " ".join(filter(None, [
                    f"abstract: {row['abstract']}" if row['abstract'] else None,
                    f"editor_summary: {row['editor_summary']}" if row['editor_summary'] else None,
                    f"structured_abstract: {row['structured_abstract']}" if row['structured_abstract'] else None
                ])) for row in rows
            ]
            return abstracts

    def build_batch(self, abstracts):
        """
        {
        "custom_id": "1",
        "method": "POST",
        "url": "/v1/chat/ds-test",
        "body": {
            "model": "batch-test-model",
            "messages": [
            { "role": "system", "content": "You are a helpful assistant." },
            { "role": "user", "content": "你好！有什么可以帮助你的吗？" }
            ]
        }
        }
        """
        jsons = []
        for i, abstract in enumerate(abstracts[0:10]):
            entry = {
                "custom_id": f"request-{i}",
                "method": "POST",
                "url": "/v1/chat/completions",
                "body": {
                    "model": "qwen-plus", 
                    "messages": [
                        {"role": "user", "content": abstract}
                    ],
                }
            }
            jsons.append(json.dumps(entry, ensure_ascii=False))
        
        # 将列表转换为换行符分隔的字符串，并转换为字节流
        jsonl_content = "\n".join(jsons).encode("utf-8")
        file_io = io.BytesIO(jsonl_content)

        file_id = self.app.files.create(
            file=("batch_input.jsonl", file_io),
            purpose="batch"
        ).id
        
        batch_id = self.app.batches.create(
            input_file_id=file_id, 
            endpoint="/v1/chat/completions", 
            completion_window="24h"
        ).id

        result_id = None
        while True:
            time.sleep(20)
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

    def generate_summary(self, texts):
        pass


if __name__ == "__main__":
    service = LLMService()
    abstracts = service.build_batch(service.get_abstracts())