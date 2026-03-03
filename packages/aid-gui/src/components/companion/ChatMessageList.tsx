import React, { useEffect, useRef } from 'react';
import { Bot, Loader2 } from 'lucide-react';
import { md } from '../../lib/companion';
import { HintButtons } from './HintButtons';
import type { CompanionMessage } from '../../types/api';

// ---------------------------------------------------------------------------
// MsgBubble
// ---------------------------------------------------------------------------

export const MsgBubble: React.FC<{ msg: CompanionMessage }> = React.memo(({ msg }) => {
  if (msg.role === 'user') {
    return (
      <div className="flex justify-end">
        <div className="max-w-[80%] bg-state-executing/20 text-white/90 rounded-2xl rounded-br-sm px-3 py-2 text-sm whitespace-pre-wrap">
          {msg.content}
        </div>
      </div>
    );
  }
  return (
    <div className="flex gap-2 items-start">
      <div className="w-6 h-6 rounded-full bg-state-executing/20 flex items-center justify-center shrink-0 mt-0.5">
        <Bot size={14} className="text-state-executing" />
      </div>
      <div className="max-w-[85%] space-y-1">
        <div
          className="prose prose-invert prose-sm max-w-none bg-white/5 rounded-2xl rounded-tl-sm px-3 py-2 text-sm text-white/80"
          dangerouslySetInnerHTML={{ __html: md(msg.content) }}
        />
        {msg.model && <span className="text-[10px] text-white/15 pl-1">{msg.model}</span>}
      </div>
    </div>
  );
});
MsgBubble.displayName = 'MsgBubble';

// ---------------------------------------------------------------------------
// ChatMessageList
// ---------------------------------------------------------------------------

export interface ChatMessageListProps {
  messages: CompanionMessage[];
  streaming: boolean;
  streamText: string;
  onHint: (prompt: string) => void;
  onFocusInput: () => void;
  /** 'full' shows large empty state; 'compact' shows minimal placeholder */
  variant: 'full' | 'compact';
  className?: string;
}

export const ChatMessageList: React.FC<ChatMessageListProps> = ({
  messages,
  streaming,
  streamText,
  onHint,
  onFocusInput,
  variant,
  className,
}) => {
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length, streamText]);

  return (
    <div className={className ?? 'flex-1 overflow-y-auto custom-scrollbar px-4 py-4 space-y-4'}>
      {messages.length === 0 && !streaming && (
        <div className="flex flex-col items-center justify-center h-full text-center space-y-4">
          <Bot size={variant === 'full' ? 32 : 24} className="text-white/20 opacity-50" />
          <p className="text-sm text-white/30">
            {variant === 'full'
              ? 'Start a conversation with your AID project companion.'
              : 'Ask anything about your project.'}
          </p>
          <HintButtons onHint={onHint} onFocus={onFocusInput} variant={variant} />
          <p className="text-[11px] text-white/15">Or type a message below</p>
        </div>
      )}
      {messages.map((m) => (
        <MsgBubble key={m.id} msg={m} />
      ))}
      {streaming && streamText && (
        <div className="flex gap-2 items-start">
          <div className="w-6 h-6 rounded-full bg-state-executing/20 flex items-center justify-center shrink-0 mt-0.5">
            <Bot size={14} className="text-state-executing" />
          </div>
          <div
            className="prose prose-invert prose-sm max-w-none bg-white/5 rounded-2xl rounded-tl-sm px-3 py-2 text-sm text-white/80"
            dangerouslySetInnerHTML={{
              __html: md(streamText) + '<span class="streaming-cursor">&#9610;</span>',
            }}
          />
        </div>
      )}
      {streaming && !streamText && (
        <div className="flex gap-2 items-center">
          <div className="w-6 h-6 rounded-full bg-state-executing/20 flex items-center justify-center shrink-0">
            <Loader2 size={14} className="text-state-executing animate-spin" />
          </div>
          <span className="text-xs text-white/30">Thinking...</span>
        </div>
      )}
      <div ref={bottomRef} />
    </div>
  );
};
