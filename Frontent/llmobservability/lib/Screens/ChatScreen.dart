import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  String? _lastCallId;

  final String backendUrl = "http://localhost:8000"; // Your FastAPI Ollama backend

  @override
  void initState() {
    super.initState();
    // Optional: Add a welcome message
    // _addAssistantMessage("Hello! I'm powered by Llama2 running locally via Ollama. Ask me anything!");
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    final userMessage = {
      "role": "user",
      "content": text.trim(),
      "timestamp": DateTime.now(),
    };

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse("$backendUrl/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"question": text.trim()}),
        //timeout:  Duration(seconds: 180), // Adjust if needed
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final answer = data["response"] as String;
        final callId = data["call_id"] as String?;

        final assistantMessage = {
          "role": "assistant",
          "content": answer,
          "timestamp": DateTime.now(),
        };

        setState(() {
          _messages.add(assistantMessage);
          _lastCallId = callId;
          _isLoading = false;
        });
      } else {
        _addErrorMessage("Server error: ${response.statusCode}\n${response.body}");
      }
    } on Exception catch (_) {
      _addErrorMessage(
          "⚠️ Request timed out.\nThe model is taking too long. Try a simpler question or use a smaller model like llama2:3b.");
    } on http.ClientException catch (_) {
      _addErrorMessage(
          "⚠️ Connection failed.\nMake sure your FastAPI backend is running on http://localhost:8000 and Ollama is active.");
    } catch (e) {
      _addErrorMessage("⚠️ Unexpected error: $e");
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _addErrorMessage(String text) {
    setState(() {
      _messages.add({
        "role": "assistant",
        "content": text,
        "timestamp": DateTime.now(),
      });
      _isLoading = false;
    });
  }

  void _addAssistantMessage(String text) {
    setState(() {
      _messages.add({
        "role": "assistant",
        "content": text,
        "timestamp": DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  Future<void> _sendFeedback(int value) async {
    if (_lastCallId == null) return;

    try {
      await http.post(
        Uri.parse("$backendUrl/feedback"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "call_id": _lastCallId,
          "feedback": value, // 1 = good, -1 = bad
        }),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Thank you for your feedback! ${value > 0 ? '👍' : '👎'}"),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to send feedback")),
      );
    }
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _lastCallId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ollama Chat - Llama2"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: "Clear Chat",
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return _buildLoadingBubble();
                }

                final msg = _messages[index];
                final isUser = msg["role"] == "user";
                final isLatestAssistant = !isUser && index == _messages.length - 1;

                return _buildMessageBubble(
                  content: msg["content"],
                  timestamp: msg["timestamp"],
                  isUser: isUser,
                  showFeedback: isLatestAssistant && !_isLoading,
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text("Thinking...", style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required String content,
    required DateTime timestamp,
    required bool isUser,
    required bool showFeedback,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isUser ? Colors.deepPurple[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              content,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('HH:mm').format(timestamp),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          if (showFeedback) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _sendFeedback(1),
                  icon: const Icon(Icons.thumb_up, size: 16),
                  label: const Text("Good"),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.green[700]),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _sendFeedback(-1),
                  icon: const Icon(Icons.thumb_down, size: 16),
                  label: const Text("Bad"),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red[700]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(offset: const Offset(0, -2), blurRadius: 8, color: Colors.black.withOpacity(0.1)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: "Ask Llama2 anything...",
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(_controller.text),
              enabled: !_isLoading,
            ),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            onPressed: _isLoading ? null : () => _sendMessage(_controller.text),
            backgroundColor: Colors.deepPurple,
            mini: true,
            child: const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}