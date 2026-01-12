// lib/mnemonic_card.dart
import 'package:flutter/material.dart';

Widget buildAIHint(String mnemonic) {
  return Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.blue.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.blue.withOpacity(0.1)),
    ),
    child: Row(
      children: [
        Icon(Icons.psychology, color: Colors.blueAccent), // AI 图标
        SizedBox(width: 12),
        Expanded(
          child: Text(
            mnemonic,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey[800],
            ),
          ),
        ),
      ],
    ),
  );
}
