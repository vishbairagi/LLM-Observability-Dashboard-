import streamlit as st
import requests
from datetime import datetime
import json

# Page config
st.set_page_config(
    page_title="Ollama Chatbot",
    page_icon="🤖",
    layout="centered",
    initial_sidebar_state="expanded"
)

# Custom CSS for better styling
st.markdown("""
    <style>
    .stChatMessage {
        padding: 1rem;
        border-radius: 0.8rem;
        margin-bottom: 1rem;
    }
    .user-message {
        background-color: #e3f2fd;
        border-left: 4px solid #2196F3;
    }
    .assistant-message {
        background-color: #f0f0f0;
        border-left: 4px solid #4caf50;
    }
    .feedback-buttons {
        margin-top: 0.5rem;
        display: flex;
        gap: 0.5rem;
    }
    .timestamp {
        font-size: 0.75rem;
        color: #666;
        margin-top: 0.3rem;
    }
    </style>
    """, unsafe_allow_html=True)

# Backend URL
BACKEND_URL = "http://localhost:8000"

# Comprehensive system prompt with real-time knowledge injection
SYSTEM_PROMPT = """
You are a helpful, accurate AI assistant.
Always use the most up-to-date information provided below when relevant.

Current date: December 17, 2025.

Key world leaders (as of December 2025):
- Prime Minister of India: Narendra Modi (serving third term since 2014, re-elected in 2024).
- President of the United States: Donald Trump (47th President, elected in 2024, second non-consecutive term).
- President of Russia: Vladimir Putin (re-elected for fifth term in 2024).
- Chancellor of Germany: Friedrich Merz (sworn in May 2025 after February 2025 elections; previously Olaf Scholz until early 2025).
- President of France: Emmanuel Macron (second term until 2027).
- Prime Minister of the United Kingdom: Keir Starmer (since July 2024).

Recent major events (late 2024 - 2025):
- Donald Trump won the 2024 US presidential election and is the current President.
- Political instability in France and Germany: multiple government changes and no-confidence votes.
- Ongoing geopolitical tensions, including Russia-Ukraine war.
- Bitcoin reached highs above $90,000 USD in late 2024/early 2025, with fluctuations (use approximate recent values if asked).

For time-sensitive questions (news, prices, leaders, events), prioritize this information over your training data.
If asked about something not covered here, note that your knowledge is supplemented up to December 2025.
Answer concisely and factually.
"""

# Sidebar
with st.sidebar:
    st.header("🤖 Ollama Chatbot")
    st.caption("Powered by local Ollama models")
    
    if st.button("🗑️ Clear Chat History", use_container_width=True, type="secondary"):
        st.session_state.messages = []
        st.session_state.last_call_id = None
        st.rerun()
    
    st.divider()
    st.caption(f"Session started: {datetime.now().strftime('%Y-%m-%d %H:%M')}")

# Main title
st.title("💬 Ollama Local Chatbot")
st.markdown("Ask anything — your question stays private on your machine! (Injected with up-to-date knowledge up to December 2025)")

# Initialize session state
if "messages" not in st.session_state:
    st.session_state.messages = []
    st.session_state.last_call_id = None

# Display chat messages (historical)
for i, msg in enumerate(st.session_state.messages):
    role = msg["role"]
    content = msg["content"]
    timestamp = msg.get("timestamp", "")

    with st.chat_message(role, avatar="👤" if role == "user" else "🤖"):
        st.markdown(f"**{content}**")
        
        if timestamp:
            st.caption(f"{timestamp}")
        
        # Feedback buttons for assistant messages with call_id
        if role == "assistant" and "call_id" in msg:
            st.markdown("<div class='feedback-buttons'>", unsafe_allow_html=True)
            col1, col2, col3 = st.columns([1, 1, 6])
            
            with col1:
                if st.button("👍 Good", key=f"good_hist_{i}", use_container_width=True):
                    try:
                        requests.post(f"{BACKEND_URL}/feedback", 
                                    json={"call_id": msg["call_id"], "feedback": 1})
                        st.success("Thank you for your feedback!", icon="✅")
                    except:
                        st.error("Failed to send feedback")
            
            with col2:
                if st.button("👎 Bad", key=f"bad_hist_{i}", use_container_width=True):
                    try:
                        requests.post(f"{BACKEND_URL}/feedback", 
                                    json={"call_id": msg["call_id"], "feedback": -1})
                        st.success("Thank you for your feedback!", icon="✅")
                    except:
                        st.error("Failed to send feedback")
            
            st.markdown("</div>", unsafe_allow_html=True)

# Chat input
if prompt := st.chat_input("Type your message here..."):
    # Add and display user message
    user_timestamp = datetime.now().strftime("%H:%M")
    user_msg = {
        "role": "user",
        "content": prompt,
        "timestamp": user_timestamp
    }
    st.session_state.messages.append(user_msg)
    
    with st.chat_message("user", avatar="👤"):
        st.markdown(f"**{prompt}**")
        st.caption(user_timestamp)

    # Assistant response with real-time streaming
    with st.chat_message("assistant", avatar="🤖"):
        message_placeholder = st.empty()
        timestamp_placeholder = st.empty()
        full_response = ""
        call_id = None

        try:
            with st.spinner("Thinking..."):
                response = requests.post(
                    f"{BACKEND_URL}/chat",
                    json={
                        "question": prompt,
                        "stream": True,
                        "system_prompt": SYSTEM_PROMPT  # Pass the injected knowledge as system prompt
                    },
                    stream=True,
                    timeout=300
                )
                
                if response.status_code != 200:
                    st.error(f"Server error: {response.status_code} - {response.text}")
                else:
                    for line in response.iter_lines():
                        if line:
                            chunk = json.loads(line.decode("utf-8"))
                            
                            token = chunk.get("response") or chunk.get("message", {}).get("content", "")
                            if token:
                                full_response += token
                                message_placeholder.markdown(f"**{full_response}** ▏")  # Typing cursor
                            
                            if "call_id" in chunk:
                                call_id = chunk["call_id"]
                            
                            if chunk.get("done", False):
                                break

                    # Finalize display
                    message_placeholder.markdown(f"**{full_response}**")
                    assistant_timestamp = datetime.now().strftime("%H:%M")
                    timestamp_placeholder.caption(assistant_timestamp)

                    # Save to history
                    assistant_msg = {
                        "role": "assistant",
                        "content": full_response,
                        "timestamp": assistant_timestamp
                    }
                    if call_id:
                        assistant_msg["call_id"] = call_id
                    st.session_state.messages.append(assistant_msg)

                    # Feedback buttons
                    if call_id:
                        st.markdown("<div class='feedback-buttons'>", unsafe_allow_html=True)
                        col1, col2, col3 = st.columns([1, 1, 6])
                        with col1:
                            if st.button("👍 Good", key="good_live"):
                                try:
                                    requests.post(f"{BACKEND_URL}/feedback", 
                                                json={"call_id": call_id, "feedback": 1})
                                    st.success("Thanks!")
                                except:
                                    st.error("Failed to send feedback")
                        with col2:
                            if st.button("👎 Bad", key="bad_live"):
                                try:
                                    requests.post(f"{BACKEND_URL}/feedback", 
                                                json={"call_id": call_id, "feedback": -1})
                                    st.success("Thanks!")
                                except:
                                    st.error("Failed to send feedback")
                        st.markdown("</div>", unsafe_allow_html=True)

        except requests.exceptions.Timeout:
            st.error("Request timed out. The model might be taking too long to respond.")
        except requests.exceptions.ConnectionError:
            st.error("Cannot connect to backend. Is your backend running at http://localhost:8000?")
        except json.JSONDecodeError:
            st.error("Failed to parse streaming response. Check backend streaming format.")
        except Exception as e:
            st.error(f"Unexpected error: {e}")

# Footer
st.markdown("---")
st.caption("🔒 All conversations are processed locally • No data leaves your machine • Knowledge updated to December 2025")