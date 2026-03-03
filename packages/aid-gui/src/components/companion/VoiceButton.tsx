import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Mic, Square, Loader2 } from 'lucide-react';
import { cn } from '../../lib/utils';
import { useStore } from '../../store';

export interface VoiceButtonProps {
  onTranscript: (text: string) => void;
  disabled?: boolean;
  /** Compact mode — just a mic icon, no inline recording bar. */
  compact?: boolean;
}

type VoiceState = 'idle' | 'recording' | 'processing';
type Engine = 'webspeech' | 'whisper';

/**
 * Voice input button — auto-sends on stop (no confirm step).
 *
 * Detects Whisper availability on mount. If unavailable, uses Web Speech API
 * directly with live interim results (works great for Czech).
 */
export const VoiceButton: React.FC<VoiceButtonProps> = ({ onTranscript, disabled, compact }) => {
  const [state, setState] = useState<VoiceState>('idle');
  const [elapsed, setElapsed] = useState(0);
  const [liveText, setLiveText] = useState('');
  const [audioLevel, setAudioLevel] = useState(0);

  const engineRef = useRef<Engine | null>(null);
  const mediaRecRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const animFrameRef = useRef<number>(0);
  const recognitionRef = useRef<any>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const finalTextRef = useRef('');
  const interimTextRef = useRef('');

  const activeProject = useStore((s) => s.activeProject);

  // Detect engine in background on mount
  useEffect(() => {
    if (!activeProject?.id) return;
    const projectId = activeProject.id;
    (async () => {
      try {
        const form = new FormData();
        form.append('file', new Blob([new Uint8Array(44)], { type: 'audio/wav' }), 'probe.wav');
        const res = await fetch(
          `/api/p/${encodeURIComponent(projectId)}/companion/transcribe`,
          { method: 'POST', body: form },
        );
        engineRef.current = res.status !== 503 ? 'whisper' : 'webspeech';
      } catch {
        engineRef.current = 'webspeech';
      }
    })();
  }, [activeProject?.id]);

  // Clean up on unmount
  useEffect(() => () => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
    stopAllMedia();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  /* ------------------------------------------------------------------ */
  /*  Helpers                                                            */
  /* ------------------------------------------------------------------ */
  const stopAllMedia = useCallback(() => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    if (audioCtxRef.current) {
      audioCtxRef.current.close().catch(() => {});
      audioCtxRef.current = null;
    }
    if (recognitionRef.current) {
      try { recognitionRef.current.abort(); } catch { /* ignore */ }
      recognitionRef.current = null;
    }
    const rec = mediaRecRef.current;
    if (rec && rec.state === 'recording') {
      try { rec.stop(); } catch { /* ignore */ }
    }
    mediaRecRef.current = null;
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = 0;
    }
    setAudioLevel(0);
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const emitAndReset = useCallback((text: string) => {
    const t = text.trim();
    if (t) onTranscript(t);
    setLiveText('');
    finalTextRef.current = '';
    interimTextRef.current = '';
    setState('idle');
  }, [onTranscript]);

  /* ------------------------------------------------------------------ */
  /*  Audio level meter                                                  */
  /* ------------------------------------------------------------------ */
  const startLevelMeter = useCallback((stream: MediaStream) => {
    try {
      const ctx = new AudioContext();
      audioCtxRef.current = ctx;
      const source = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 256;
      source.connect(analyser);

      const data = new Uint8Array(analyser.frequencyBinCount);
      const tick = () => {
        analyser.getByteFrequencyData(data);
        const avg = data.reduce((a, b) => a + b, 0) / data.length;
        setAudioLevel(avg / 255);
        animFrameRef.current = requestAnimationFrame(tick);
      };
      tick();
    } catch { /* AudioContext not available */ }
  }, []);

  /* ------------------------------------------------------------------ */
  /*  Web Speech API — primary when Whisper unavailable                  */
  /* ------------------------------------------------------------------ */
  const startWebSpeech = useCallback(async () => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) { setState('idle'); return; }

    // Mic stream for level meter
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      startLevelMeter(stream);
    } catch { /* no visualizer */ }

    const recognition = new SR();
    recognition.lang = 'cs-CZ';
    recognition.interimResults = true;
    recognition.continuous = true;
    recognition.maxAlternatives = 1;
    recognitionRef.current = recognition;

    finalTextRef.current = '';
    interimTextRef.current = '';

    recognition.onresult = (e: any) => {
      let interim = '';
      let final = '';
      for (let i = 0; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) final += r[0].transcript;
        else interim += r[0].transcript;
      }
      finalTextRef.current = final;
      interimTextRef.current = interim;
      setLiveText(final + interim);
    };

    recognition.onerror = (e: any) => {
      if (e.error !== 'no-speech' && e.error !== 'aborted') {
        stopAllMedia();
        setState('idle');
      }
    };

    recognition.onend = () => { /* handled in stopWebSpeech */ };

    setState('recording');
    setElapsed(0);
    setLiveText('');
    timerRef.current = setInterval(() => setElapsed((p) => p + 1), 1000);
    recognition.start();
  }, [startLevelMeter, stopAllMedia]);

  const stopWebSpeech = useCallback(() => {
    if (recognitionRef.current) {
      try { recognitionRef.current.stop(); } catch { /* ignore */ }
      recognitionRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    if (audioCtxRef.current) {
      audioCtxRef.current.close().catch(() => {});
      audioCtxRef.current = null;
    }
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = 0;
    }
    setAudioLevel(0);
    if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null; }

    // Small delay to let final results arrive, then auto-send
    setTimeout(() => {
      const text = finalTextRef.current + interimTextRef.current;
      emitAndReset(text);
    }, 300);
  }, [emitAndReset]);

  /* ------------------------------------------------------------------ */
  /*  Whisper — MediaRecorder → blob → POST → auto-send                 */
  /* ------------------------------------------------------------------ */
  const startWhisperRecording = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm;codecs=opus' });
      chunksRef.current = [];

      recorder.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      recorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        streamRef.current = null;
        if (audioCtxRef.current) { audioCtxRef.current.close().catch(() => {}); audioCtxRef.current = null; }
        if (animFrameRef.current) { cancelAnimationFrame(animFrameRef.current); animFrameRef.current = 0; }
        setAudioLevel(0);

        const blob = new Blob(chunksRef.current, { type: 'audio/webm;codecs=opus' });
        if (blob.size === 0) { setState('idle'); return; }

        setState('processing');
        setLiveText('Transcribing...');
        const projectId = activeProject?.id;
        if (!projectId) { setState('idle'); return; }

        const form = new FormData();
        form.append('file', blob, 'recording.webm');

        try {
          const res = await fetch(
            `/api/p/${encodeURIComponent(projectId)}/companion/transcribe`,
            { method: 'POST', body: form },
          );
          if (res.ok) {
            const json = await res.json();
            if (json.ok && json.data?.text) {
              emitAndReset(json.data.text);
              return;
            }
          }
          engineRef.current = null;
          setState('idle');
          setLiveText('');
        } catch {
          engineRef.current = null;
          setState('idle');
          setLiveText('');
        }
      };

      mediaRecRef.current = recorder;
      recorder.start();
      setElapsed(0);
      setState('recording');
      setLiveText('');
      timerRef.current = setInterval(() => setElapsed((p) => p + 1), 1000);
      startLevelMeter(stream);
    } catch {
      setState('idle');
    }
  }, [activeProject, startLevelMeter, emitAndReset]);

  const stopWhisperRecording = useCallback(() => {
    if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null; }
    const rec = mediaRecRef.current;
    if (rec && rec.state === 'recording') {
      rec.stop();
      mediaRecRef.current = null;
    }
  }, []);

  /* ------------------------------------------------------------------ */
  /*  Unified start / stop                                               */
  /* ------------------------------------------------------------------ */
  const startRecording = useCallback(async () => {
    const engine = engineRef.current ?? 'webspeech';
    if (engine === 'whisper') startWhisperRecording();
    else startWebSpeech();
  }, [startWhisperRecording, startWebSpeech]);

  const stopRecording = useCallback(() => {
    const engine = engineRef.current;
    if (engine === 'whisper') stopWhisperRecording();
    else stopWebSpeech();
  }, [stopWhisperRecording, stopWebSpeech]);

  const handleMicClick = useCallback(() => {
    if (state === 'recording') stopRecording();
    else if (state === 'idle') startRecording();
  }, [state, startRecording, stopRecording]);

  const isDisabled = disabled || !activeProject || state === 'processing';
  const formatTime = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;

  // Compact mode: just a mic icon button (for Topbar search bar)
  if (compact && state === 'idle') {
    return (
      <button
        type="button"
        onClick={handleMicClick}
        disabled={isDisabled}
        title="Voice input"
        className={cn(
          'p-1 rounded-lg transition-all',
          isDisabled
            ? 'text-white/20 cursor-not-allowed'
            : 'text-white/30 hover:text-white/60 hover:bg-white/10',
        )}
      >
        <Mic size={14} />
      </button>
    );
  }

  // Recording bar
  if (state === 'recording') {
    return (
      <div className="flex items-center gap-2 w-full">
        <div className="flex items-center gap-[2px] h-6 min-w-[48px]">
          {Array.from({ length: 12 }).map((_, i) => {
            const barH = Math.max(3, Math.min(22, audioLevel * 22 + Math.sin(Date.now() / 100 + i * 0.7) * 4));
            return (
              <div
                key={i}
                className="w-[3px] rounded-full bg-red-400 transition-all duration-75"
                style={{ height: `${barH}px` }}
              />
            );
          })}
        </div>
        <span className="text-xs font-mono text-red-400 tabular-nums min-w-[36px]">
          {formatTime(elapsed)}
        </span>
        <span className="text-[10px] text-white/30 tracking-wider flex-1 truncate">
          {liveText || 'Recording...'}
        </span>
        <button
          type="button"
          onClick={stopRecording}
          className="p-1.5 rounded-lg bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-colors"
          title="Stop & send"
        >
          <Square size={14} />
        </button>
      </div>
    );
  }

  // Processing (Whisper transcription)
  if (state === 'processing') {
    return (
      <div className="flex items-center gap-2 w-full">
        <Loader2 size={16} className="text-amber-400 animate-spin" />
        <span className="text-xs text-amber-400/70">Transcribing...</span>
      </div>
    );
  }

  // Idle — mic button
  return (
    <button
      type="button"
      onClick={handleMicClick}
      disabled={isDisabled}
      aria-label="Start voice input"
      title="Voice input"
      className={cn(
        'p-2 rounded-xl transition-all shrink-0',
        isDisabled
          ? 'text-white/20 cursor-not-allowed'
          : 'text-white/40 hover:text-white/70 hover:bg-white/5',
      )}
    >
      <Mic size={16} />
    </button>
  );
};
