import streamlit as st
import requests

# Simple Streamlit Chatbot using Ollama via backend
st.set_page_config(page_title="Simple Chatbot", layout="wide")
st.title("Simple Ollama Chatbot")

# Backend URL
BACKEND_URL = "http://localhost:8000"

# Initialize chat history
if "messages" not in st.session_state:
    st.session_state.messages = []
    st.session_state.last_call_id = None  # To track last call for feedback

# Display chat history
for i, msg in enumerate(st.session_state.messages):
    with st.chat_message(msg["role"]):
        st.write(msg["content"])
        if msg["role"] == "assistant" and i == len(st.session_state.messages) - 1:
            # Feedback buttons for last response
            col1, col2 = st.columns(2)
            if col1.button("👍 Good", key=f"good_{i}"):
                requests.post(f"{BACKEND_URL}/feedback", json={"call_id": st.session_state.last_call_id, "feedback": 1})
                st.success("Thanks for the feedback!")
            if col2.button("👎 Bad", key=f"bad_{i}"):
                requests.post(f"{BACKEND_URL}/feedback", json={"call_id": st.session_state.last_call_id, "feedback": -1})
                st.success("Thanks for the feedback!")

# User input
if prompt := st.chat_input("Ask something..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.write(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Thinking..."):
            try:
                response = requests.post(f"{BACKEND_URL}/chat", json={"question": prompt}, timeout=200)
                if response.status_code == 200:
                    data = response.json()
                    answer = data["response"]
                    call_id = data.get("call_id")  # Get ID for feedback
                    st.write(answer)
                    st.session_state.messages.append({"role": "assistant", "content": answer})
                    st.session_state.last_call_id = call_id
                else:
                    st.error(f"Error {response.status_code}: {response.text}")
            except requests.exceptions.RequestException as e:
                st.error(f"Connection failed: {e}")