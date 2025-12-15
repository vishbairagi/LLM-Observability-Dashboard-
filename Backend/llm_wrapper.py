import time, uuid
from models import llm_calls
import openai

def call_llm(prompt, user_id):
    request_id = str(uuid.uuid4())
    start = time.time()

    try:
        response = openai.ChatCompletion.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}]
        )

        latency = int((time.time() - start) * 1000)

        record = {
            "request_id": request_id,
            "user_id": user_id,
            "model": "gpt-4o-mini",
            "prompt_tokens": response.usage.prompt_tokens,
            "completion_tokens": response.usage.completion_tokens,
            "total_tokens": response.usage.total_tokens,
            "latency_ms": latency,
            "status": "success",
            "timestamp": time.time()
        }

        llm_calls.insert_one(record)
        return response.choices[0].message.content

    except Exception as e:
        llm_calls.insert_one({
            "request_id": request_id,
            "user_id": user_id,
            "status": "error",
            "error": str(e),
            "timestamp": time.time()
        })
        raise e
