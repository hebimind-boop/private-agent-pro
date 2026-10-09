enum UserIntent {
  chat,
  action,
}

/// Orchestrates intent classification for user inputs to prevent casual
/// conversational prompts (e.g. "hii", "hello", general queries) from triggering
/// unintended Android UI automations or accessibility screen actions.
class AgentOrchestrator {
  // Regex matching casual greetings and conversational hellos
  static final RegExp _greetingRegex = RegExp(
    r'^(hi|hii+|hey+|hello+|yo|sup|howdy|hola|greetings|good\s+(morning|afternoon|evening|night)|what(?:\x27s|\s+is)\s+up|whats\s+up)\b[!?.,\s]*$',
    caseSensitive: false,
  );

  // Regex matching social conversation expressions and courteous remarks
  static final RegExp _conversationalPhrasesRegex = RegExp(
    r'^(how\s+are\s+you|who\s+are\s+you|who\s+made\s+you|what\s+can\s+you\s+do|what\s+are\s+your\s+features|tell\s+me\s+a\s+joke|thank\s+you|thanks|thx|bye|goodbye|see\s+ya|ok|okay|cool|nice|awesome|great|sounds\s+good|haha|lol)\b[!?.,\s]*$',
    caseSensitive: false,
  );

  // Common informational inquiry patterns (pure Q&A, knowledge, coding, writing)
  static final RegExp _informationalQueryRegex = RegExp(
    r'^(what\s+is|what\s+are|who\s+is|who\s+was|where\s+is|when\s+is|when\s+did|why\s+is|why\s+do|why\s+does|how\s+does|how\s+do\s+i|how\s+can\s+i|explain|tell\s+me\s+about|summarize|define|translate|write\s+a|compose\s+a|generate\s+a|draft\s+an|code\s+a|write\s+code|solve|calculate|give\s+me\s+a\s+list|suggest\s+some|can\s+you\s+(help|explain|write))\b',
    caseSensitive: false,
  );

  // Screen reading queries that should be treated as actions
  static final RegExp _screenReadingRegex = RegExp(
    r'\b(what(?:\x27s|\s+is)\s+on\s+(my\s+)?screen|read\s+screen|check\s+screen|look\s+at\s+screen)\b',
    caseSensitive: false,
  );

  // Explicit device automation commands & action triggers
  static final RegExp _actionTriggersRegex = RegExp(
    r'(\b(open|launch|start)\s+[a-zA-Z0-9_\s]+|'
    r'\b(click|tap|press)\s+[a-zA-Z0-9_\s]+|'
    r'\b(scroll|swipe)\s+(up|down|left|right)?|'
    r'\b(type|enter|input)\s+[a-zA-Z0-9_\s]+|'
    r'\b(set|change|adjust)\s+(volume|brightness|sound|screen|alarm|timer)|'
    r'\b(volume|brightness)\s+(to\s+)?\d+%?|'
    r'\b(turn\s+(on|off)|enable|disable|toggle)\s+(wifi|bluetooth|torch|flashlight|hotspot|airplane\s+mode|dark\s+mode|silent\s+mode|volume|sound)|'
    r'\b(mute|unmute)\b|'
    r'\b(call|dial|phone)\s+[a-zA-Z0-9_\s]+|'
    r'\b(send|text)\s+(a\s+)?(message|sms|msg|whatsapp|email)?(\s*to\s+[a-zA-Z0-9_\s]+)?|'
    r'\b(play\s+.+\s+on\s+(youtube|spotify|music))|'
    r'\b(search\s+for\s+.+\s+(on|in)\s+(youtube|google|chrome|spotify|amazon|play\s+store|maps))|'
    r'\b(take\s+(a\s+)?screenshot)|'
    r'\b(set\s+(an?\s*)?(alarm|timer))|'
    r'\b(go\s+to\s+settings|go\s+home|press\s+back))',
    caseSensitive: false,
  );

  /// Checks whether a prompt explicitly contains a device action command.
  /// Returns false for greetings, conversational chatting, and informational queries.
  static bool isActionIntent(String prompt) {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return false;

    // 1. Explicit greeting check -> definitely NOT a device action
    if (_greetingRegex.hasMatch(cleanPrompt)) {
      return false;
    }

    // 2. Explicit conversational phrases -> definitely NOT a device action
    if (_conversationalPhrasesRegex.hasMatch(cleanPrompt)) {
      return false;
    }

    // 3. Screen reading explicitly requested -> action
    if (_screenReadingRegex.hasMatch(cleanPrompt)) {
      return true;
    }

    // 4. Informational queries without explicit device commands -> pure Chat
    if (_informationalQueryRegex.hasMatch(cleanPrompt) &&
        !_actionTriggersRegex.hasMatch(cleanPrompt)) {
      return false;
    }

    // 5. Must match an explicit device action trigger
    if (_actionTriggersRegex.hasMatch(cleanPrompt)) {
      return true;
    }

    // 6. If it's a general question ending with '?', default to chat unless action is specified
    if (cleanPrompt.endsWith('?') &&
        !_actionTriggersRegex.hasMatch(cleanPrompt)) {
      return false;
    }

    // Default: If no action verb is identified, treat as conversational chat
    return false;
  }

  /// Classifies user prompt into UserIntent.action or UserIntent.chat.
  static UserIntent classifyIntent(String prompt) {
    return isActionIntent(prompt) ? UserIntent.action : UserIntent.chat;
  }
}
