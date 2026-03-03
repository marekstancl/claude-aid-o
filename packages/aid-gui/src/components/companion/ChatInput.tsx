import React, { useState, useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { Send, Square } from 'lucide-react';
import { cn } from '../../lib/utils';
import { abortCompanionStream } from '../../lib/companion';
import { VoiceButton } from './VoiceButton';
import { HintButtons } from './HintButtons';

// ---------------------------------------------------------------------------
// ChatInput
// ---------------------------------------------------------------------------

export interface ChatInputProps {
  onSend: (text: string) => void;
  disabled: boolean;
  streaming: boolean;
  placeholder: string;
  /** Show compact hint buttons above input when messages exist */
  showHints: boolean;
  onHint: (prompt: string) => void;
  onFocusInput: () => void;
  onTranscript?: (text: string) => void;
  className?: string;
}

export interface ChatInputHandle {
  focus: () => void;
  setValue: (text: string) => void;
}

export const ChatInput = forwardRef<ChatInputHandle, ChatInputProps>(
  ({ onSend, disabled, streaming, placeholder, showHints, onHint, onFocusInput, onTranscript, className }, ref) => {
    const [input, setInput] = useState('');
    const taRef = useRef<HTMLTextAreaElement>(null);

    useImperativeHandle(ref, () => ({
      focus: () => taRef.current?.focus(),
      setValue: (text: string) => setInput(text),
    }));

    const handleSend = useCallback(() => {
      const t = input.trim();
      if (!t || streaming) return;
      setInput('');
      if (taRef.current) taRef.current.style.height = 'auto';
      onSend(t);
    }, [input, streaming, onSend]);

    const onKeyDown = useCallback(
      (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          handleSend();
        }
      },
      [handleSend],
    );

    const onInput = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
      setInput(e.target.value);
      e.target.style.height = 'auto';
      e.target.style.height = `${Math.min(e.target.scrollHeight, 120)}px`;
    }, []);

    const handleTranscript = useCallback(
      (text: string) => {
        setInput((prev) => (prev ? `${prev} ${text}` : text));
        taRef.current?.focus();
        onTranscript?.(text);
      },
      [onTranscript],
    );

    return (
      <div className={className ?? 'px-4 py-3 border-t border-white/5 shrink-0'}>
        {showHints && !streaming && (
          <HintButtons onHint={onHint} onFocus={onFocusInput} variant="compact" />
        )}
        <div className="flex items-end gap-2 bg-white/5 rounded-2xl px-3 py-2">
          <textarea
            ref={taRef}
            value={input}
            onChange={onInput}
            onKeyDown={onKeyDown}
            placeholder={placeholder}
            disabled={disabled}
            rows={1}
            className="flex-1 bg-transparent text-sm resize-none focus:outline-none placeholder:text-white/20 max-h-[120px] py-1"
          />
          <VoiceButton onTranscript={handleTranscript} disabled={disabled || streaming} />
          {streaming ? (
            <button
              onClick={abortCompanionStream}
              className="p-2 rounded-xl bg-red-500/80 text-white hover:bg-red-500 transition-all shrink-0"
              aria-label="Stop generating"
              title="Stop generating"
            >
              <Square size={14} />
            </button>
          ) : (
            <button
              onClick={handleSend}
              disabled={!input.trim() || disabled}
              className={cn(
                'p-2 rounded-xl transition-all shrink-0',
                input.trim()
                  ? 'bg-state-executing text-white hover:brightness-110'
                  : 'text-white/20 cursor-not-allowed',
              )}
              aria-label="Send message"
            >
              <Send size={16} />
            </button>
          )}
        </div>
        <div className="flex items-center justify-between mt-2 px-1">
          <span className="text-[10px] text-white/15">Shift+Enter for new line</span>
        </div>
      </div>
    );
  },
);

ChatInput.displayName = 'ChatInput';
