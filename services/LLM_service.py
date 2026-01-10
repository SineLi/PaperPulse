from db.database import get_db_connection
import time
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


    def generate_summary(self, texts):
        pass


if __name__ == "__main__":
    service = LLMService()
    abstracts = service.build_batch(service.get_abstracts())