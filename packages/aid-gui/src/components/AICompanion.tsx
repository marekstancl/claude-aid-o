import React, { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Search, Mic, Sparkles, X, Command, ArrowRight, History, Zap, MessageSquare, Gavel } from 'lucide-react';
import { cn } from '../lib/utils';

interface AICompanionProps {
  isOpen: boolean;
  onClose: () => void;
}

const presets = [
  { icon: Zap, label: "What's the status of my pipeline?", query: "pipeline status" },
  { icon: History, label: "Show me lessons from the last 3 runs", query: "lessons learned" },
  { icon: Sparkles, label: "What should I work on next?", query: "next tasks" },
  { icon: MessageSquare, label: "Summarize recent decisions", query: "recent decisions" },
  { icon: Gavel, label: "Run a health check", query: "health check" },
];

export const AICompanion: React.FC<AICompanionProps> = ({ isOpen, onClose }) => {
  const [query, setQuery] = useState('');
  const [isListening, setIsListening] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const recognitionRef = useRef<any>(null);

  useEffect(() => {
    if (typeof window !== 'undefined' && ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window)) {
      const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
      recognitionRef.current = new SpeechRecognition();
      recognitionRef.current.continuous = false;
      recognitionRef.current.interimResults = true;

      recognitionRef.current.onresult = (event: any) => {
        const transcript = Array.from(event.results)
          .map((result: any) => result[0])
          .map((result: any) => result.transcript)
          .join('');
        setQuery(transcript);
      };

      recognitionRef.current.onerror = (event: any) => {
        console.error('Speech recognition error', event.error);
        setIsListening(false);
      };

      recognitionRef.current.onend = () => {
        setIsListening(false);
      };
    }
  }, []);

  const toggleListening = () => {
    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
    } else {
      setQuery('');
      recognitionRef.current?.start();
      setIsListening(true);
    }
  };

  useEffect(() => {
    if (isOpen) {
      inputRef.current?.focus();
    }
  }, [isOpen]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-bg-base/80 backdrop-blur-xl z-[100]"
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: -20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: -20 }}
            className="fixed left-1/2 top-1/4 -translate-x-1/2 w-full max-w-2xl bg-surface-2 border border-white/10 rounded-[2rem] shadow-2xl z-[101] overflow-hidden"
          >
            <div className="p-6 border-b border-white/5 relative">
              <div className="absolute left-8 top-1/2 -translate-y-1/2 text-state-executing">
                <Sparkles size={20} />
              </div>
              <input
                ref={inputRef}
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Ask anything about your orchestration..."
                className="w-full bg-transparent pl-12 pr-12 py-2 text-lg focus:outline-none placeholder:text-white/20"
              />
              <div className="absolute right-8 top-1/2 -translate-y-1/2 flex items-center gap-3">
                <button 
                  onClick={toggleListening}
                  className={cn(
                    "p-2 rounded-xl transition-all relative",
                    isListening ? "bg-state-error/20 text-state-error" : "hover:bg-white/5 text-white/40 hover:text-white"
                  )}
                >
                  {isListening && (
                    <span className="absolute inset-0 rounded-xl bg-state-error/20 animate-ping" />
                  )}
                  <Mic size={18} />
                </button>
                <button onClick={onClose} className="p-2 hover:bg-white/5 rounded-xl text-white/40 hover:text-white transition-colors">
                  <X size={18} />
                </button>
              </div>
            </div>

            <div className="p-4 max-h-[400px] overflow-y-auto custom-scrollbar">
              {!query ? (
                <div className="space-y-6 p-2">
                  <section>
                    <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3 px-2">Presets</h4>
                    <div className="grid grid-cols-1 gap-1">
                      {presets.map((preset) => (
                        <button
                          key={preset.label}
                          onClick={() => setQuery(preset.query)}
                          className="flex items-center gap-3 w-full p-3 rounded-xl hover:bg-white/5 text-left transition-all group"
                        >
                          <div className="p-2 rounded-lg bg-white/5 text-white/40 group-hover:text-state-executing transition-colors">
                            <preset.icon size={16} />
                          </div>
                          <span className="text-sm font-medium text-white/60 group-hover:text-white">{preset.label}</span>
                          <ArrowRight size={14} className="ml-auto opacity-0 group-hover:opacity-100 transition-all -translate-x-2 group-hover:translate-x-0" />
                        </button>
                      ))}
                    </div>
                  </section>

                  <section>
                    <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40 mb-3 px-2">Recent Queries</h4>
                    <div className="space-y-1">
                      <button className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-white/5 text-left text-xs text-white/40 hover:text-white/60 transition-all">
                        <History size={14} />
                        <span>"Why did gate lint_pass fail yesterday?"</span>
                      </button>
                      <button className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-white/5 text-left text-xs text-white/40 hover:text-white/60 transition-all">
                        <History size={14} />
                        <span>"Compare run performance this week"</span>
                      </button>
                    </div>
                  </section>
                </div>
              ) : (
                <div className="p-4 text-center space-y-4">
                  <div className="w-12 h-12 rounded-full border-2 border-state-executing/20 border-t-state-executing animate-spin mx-auto" />
                  <p className="text-sm text-white/40">Searching knowledge base and project context...</p>
                </div>
              )}
            </div>

            <div className="p-4 bg-white/[0.02] border-t border-white/5 flex items-center justify-between px-6">
              <div className="flex items-center gap-4 text-[10px] text-white/20 font-bold uppercase tracking-widest">
                <div className="flex items-center gap-1.5">
                  <span className="bg-white/10 px-1.5 py-0.5 rounded text-white/40">ENTER</span>
                  <span>to search</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <span className="bg-white/10 px-1.5 py-0.5 rounded text-white/40">ESC</span>
                  <span>to close</span>
                </div>
              </div>
              <div className="flex items-center gap-2 text-[10px] text-white/20 font-bold uppercase tracking-widest">
                <Command size={12} />
                <span>Powered by AID Intelligence</span>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};
