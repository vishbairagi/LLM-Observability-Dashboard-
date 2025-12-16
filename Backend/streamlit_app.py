import streamlit as st
import requests
from datetime import datetime

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
st.markdown("Ask anything — your question stays private on your machine!")

# Initialize session state
if "messages" not in st.session_state:
    st.session_state.messages = []
    st.session_state.last_call_id = None

# Display chat messages
for i, msg in enumerate(st.session_state.messages):
    role = msg["role"]
    content = msg["content"]
    timestamp = msg.get("timestamp", "")

    with st.chat_message(role, avatar="👤" if role == "user" else "🤖"):
        st.markdown(f"**{content}**")
        
        if timestamp:
            st.caption(f"{timestamp}")
        
        # Feedback buttons only for the latest assistant message
        if role == "assistant" and i == len(st.session_state.messages) - 1:
            st.markdown("<div class='feedback-buttons'>", unsafe_allow_html=True)
            col1, col2, col3 = st.columns([1, 1, 6])
            
            with col1:
                if st.button("👍 Good", key=f"good_{i}", use_container_width=True):
                    try:
                        requests.post(f"{BACKEND_URL}/feedback", 
                                    json={"call_id": st.session_state.last_call_id, "feedback": 1})
                        st.success("Thank you for your feedback!", icon="✅")
                    except:
                        st.error("Failed to send feedback")
            
            with col2:
                if st.button("👎 Bad", key=f"bad_{i}", use_container_width=True):
                    try:
                        requests.post(f"{BACKEND_URL}/feedback", 
                                    json={"call_id": st.session_state.last_call_id, "feedback": -1})
                        st.success("Thank you for your feedback!", icon="✅")
                    except:
                        st.error("Failed to send feedback")
            
            st.markdown("</div>", unsafe_allow_html=True)

# Chat input
if prompt := st.chat_input("Type your message here..."):
    # Add user message
    user_msg = {
        "role": "user",
        "content": prompt,
        "timestamp": datetime.now().strftime("%H:%M")
    }
    st.session_state.messages.append(user_msg)
    
    # Display user message immediately
    with st.chat_message("user", avatar="👤"):
        st.markdown(f"**{prompt}**")
        st.caption(user_msg["timestamp"])

    # Get assistant response
    with st.chat_message("assistant", avatar="🤖"):
        with st.spinner("Thinking..."):
            message_placeholder = st.empty()
            try:
                response = requests.post(
                    f"{BACKEND_URL}/chat",
                    json={"question": prompt},
                    timeout=200
                )
                
                if response.status_code == 200:
                    data = response.json()
                    answer = data["response"]
                    call_id = data.get("call_id")
                    
                    # Display response
                    message_placeholder.markdown(f"**{answer}**")
                    st.caption(datetime.now().strftime("%H:%M"))
                    
                    # Add to history
                    assistant_msg = {
                        "role": "assistant",
                        "content": answer,
                        "timestamp": datetime.now().strftime("%H:%M")
                    }
                    st.session_state.messages.append(assistant_msg)
                    st.session_state.last_call_id = call_id
                    
                    # Feedback buttons
                    st.markdown("<div class='feedback-buttons'>", unsafe_allow_html=True)
                    col1, col2, col3 = st.columns([1, 1, 6])
                    with col1:
                        if st.button("👍 Good", key=f"good_live_{len(st.session_state.messages)}"):
                            requests.post(f"{BACKEND_URL}/feedback", 
                                        json={"call_id": call_id, "feedback": 1})
                            st.success("Thanks!")
                    with col2:
                        if st.button("👎 Bad", key=f"bad_live_{len(st.session_state.messages)}"):
                            requests.post(f"{BACKEND_URL}/feedback", 
                                        json={"call_id": call_id, "feedback": -1})
                            st.success("Thanks!")
                    st.markdown("</div>", unsafe_allow_html=True)
                    
                else:
                    st.error(f"Server error: {response.status_code} - {response.text}")
                    
            except requests.exceptions.Timeout:
                st.error("Request timed out. The model might be taking too long to respond.")
            except requests.exceptions.ConnectionError:
                st.error("Cannot connect to backend. Is Ollama running at http://localhost:8000?")
            except Exception as e:
                st.error(f"Unexpected error: {e}")

# Footer
st.markdown("---")
st.caption("🔒 All conversations are processed locally • No data leaves your machine")