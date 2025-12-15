import os
import time
from datetime import datetime
from typing import Any, Dict, List
from contextlib import asynccontextmanager

from bson import ObjectId
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from motor.motor_asyncio import AsyncIOMotorClient
from langchain_ollama import ChatOllama
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.outputs import LLMResult
from dotenv import load_dotenv
import tiktoken

load_dotenv()

# ==================== MONGODB SETUP ====================
MONGODB_URL = os.getenv("MONGODB_URL")

if not MONGODB_URL:
    raise ValueError("Please set MONGODB_URL in .env file!")

client = AsyncIOMotorClient(MONGODB_URL)
db = client.llm_observability
collection = db.calls

# ==================== TOKEN COUNTER (Approximate) ====================
try:
    encoder = tiktoken.encoding_for_model("gpt-4")
except:
    encoder = tiktoken.get_encoding("cl100k_base")  # Fallback

# ==================== CALLBACK HANDLER ====================
class MongoCallbackHandler(BaseCallbackHandler):
    def __init__(self):
        self.start_time: float | None = None
        self.input: str = ""
        self.output: str = ""
        self.call_id: str | None = None

    def on_llm_start(self, serialized: Dict[str, Any], prompts: List[str], **kwargs) -> None:
        self.start_time = time.time()
        self.input = prompts[0] if prompts else ""

    async def on_llm_end(self, response: LLMResult, **kwargs) -> None:
        if self.start_time is None:
            return
        latency = time.time() - self.start_time
        self.output = response.generations[0][0].text if response.generations else ""

        prompt_tokens = len(encoder.encode(self.input))
        completion_tokens = len(encoder.encode(self.output))
        total_tokens = prompt_tokens + completion_tokens

        doc = {
            "timestamp": datetime.utcnow(),
            "input": self.input,
            "output": self.output,
            "latency_sec": round(latency, 2),
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
            "error": None,
            "feedback": None,
        }

        result = await collection.insert_one(doc)
        self.call_id = str(result.inserted_id)

    async def on_llm_error(self, error: Exception, **kwargs) -> None:
        latency = (time.time() - self.start_time) if self.start_time else 0.0

        doc = {
            "timestamp": datetime.utcnow(),
            "input": self.input,
            "latency_sec": round(latency, 2),
            "error": str(error),
            "feedback": None,
        }

        result = await collection.insert_one(doc)
        self.call_id = str(result.inserted_id)

# ==================== LLM SETUP ====================
llm = ChatOllama(
    model="llama2",  # You have this model! Change to "llama3.2" after downloading
    base_url="http://localhost:11434",
    temperature=0.7,
)

prompt = ChatPromptTemplate.from_messages([("human", "{question}")])
chain = prompt | llm

# ==================== LIFESPAN (Modern FastAPI) ====================
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Test MongoDB connection
    try:
        await client.admin.command("ping")
        print("✅ MongoDB connected successfully!")
    except Exception as e:
        print(f"❌ MongoDB connection failed: {e}")

    yield  # App runs here

    # Shutdown: Clean up
    print("Shutting down... Closing MongoDB client")
    client.close()

# ==================== FASTAPI APP ====================
app = FastAPI(
    title="LLM Observability Backend",
    description="Ollama + MongoDB + Observability",
    lifespan=lifespan
)

# ==================== MODELS ====================
class Query(BaseModel):
    question: str

class Feedback(BaseModel):
    call_id: str
    feedback: int  # 1 = good, -1 = bad

# ==================== ROUTES ====================
@app.post("/chat")
async def chat(query: Query):
    callback = MongoCallbackHandler()
    try:
        response = await chain.ainvoke(
            {"question": query.question},
            config={"callbacks": [callback]}
        )
        return {
            "response": response.content,
            "call_id": callback.call_id or "unknown"
        }
    except Exception as e:
        # Log error via callback
        await callback.on_llm_error(e)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/feedback")
async def feedback(fb: Feedback):
    try:
        await collection.update_one(
            {"_id": ObjectId(fb.call_id)},
            {"$set": {"feedback": fb.feedback}}
        )
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=400, detail="Invalid call_id or update failed")

@app.get("/analytics/summary")
async def summary():
    pipeline = [
        {"$group": {
            "_id": None,
            "total_calls": {"$sum": 1},
            "avg_latency": {"$avg": "$latency_sec"},
            "total_tokens": {"$sum": "$total_tokens"},
            "errors": {"$sum": {"$cond": [{"$ne": ["$error", None]}, 1, 0]}},
            "positive_feedback": {"$sum": {"$cond": [{"$eq": ["$feedback", 1]}, 1, 0]}},
            "negative_feedback": {"$sum": {"$cond": [{"$eq": ["$feedback", -1]}, 1, 0]}}
        }}
    ]
    result = await collection.aggregate(pipeline).to_list(1)
    if result:
        return result[0]
    return {
        "total_calls": 0,
        "avg_latency": 0,
        "total_tokens": 0,
        "errors": 0,
        "positive_feedback": 0,
        "negative_feedback": 0
    }

@app.get("/analytics/recent")
async def recent(limit: int = 100):
    calls = await collection.find() \
        .sort("timestamp", -1) \
        .limit(limit) \
        .to_list(limit)
    
    # Convert ObjectId to string for JSON
    for call in calls:
        call["_id"] = str(call["_id"])
    
    return calls

@app.get("/")
async def root():
    return {"message": "LLM Observability Backend is running!"}