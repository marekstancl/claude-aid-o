import React, { useState, useRef, useCallback } from 'react';
import { Mic } from 'lucide-react';
import { cn } from '../../lib/utils';
import { useStore } from '../../store';

export interface VoiceButtonProps {
  onTranscript: (text: string) => void;
  disabled?: boolean;
}

type RecordingState = 'idle' | 'recording' | 'processing';

/** Mic button: push-to-talk with Whisper transcription + Web Speech API fallback. */
export const VoiceButton: React.FC<VoiceButtonProps> = ({ onTranscript, disabled }) => {
  const [state, setState] = useState<RecordingState>('idle');
  const mediaRecRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);

  const activeProject = useStore((s) => s.activeProject);

  /* ------------------------------------------------------------------ */
  /*  Web Speech API fallback (used when Whisper returns 503)           */
  /* ------------------------------------------------------------------ */
  const fallbackWebSpeech = useCallback(() => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) {
      setState('idle');
      return;
    }
    const recognition = new SR();
    recognition.lang = 'en-US';
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;

    recognition.onresult = (e: any) => {
      const text = e.results?.[0]?.[0]?.transcript;
      if (text) onTranscript(text);
      setState('idle');
    };
    recognition.onerror = () => setState('idle');
    recognition.onend = () => setState('idle');

    setState('recording');
    recognition.start();
  }, [onTranscript]);

  /* ------------------------------------------------------------------ */
  /*  Send recorded blob to POST /companion/transcribe                  */
  /* ------------------------------------------------------------------ */
  const sendToWhisper = useCallback(async (blob: Blob) => {
    const projectId = activeProject?.id;
    if (!projectId) { setState('idle'); return; }

    setState('processing');
    const form = new FormData();
    form.append('file', blob, 'recording.webm');

    try {
      const res = await fetch(
        `/api/p/${encodeURIComponent(projectId)}/companion/transcribe`,
        { method: 'POST', body: form },
      );

      if (res.status === 503) {
        // Whisper unavailable — fall back to browser speech recognition
        fallbackWebSpeech();
        return;
      }

      if (!res.ok) {
        setState('idle');
        return;
      }

      const json = await res.json();
      if (json.ok && json.data?.text) {
        onTranscript(json.data.text);
      }
    } catch {
      // Network failure — try Web Speech as best-effort fallback
      fallbackWebSpeech();
      return;
    }

    setState('idle');
  }, [activeProject, onTranscript, fallbackWebSpeech]);

  /* ------------------------------------------------------------------ */
  /*  Start / stop MediaRecorder                                        */
  /* ------------------------------------------------------------------ */
  const startRecording = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm;codecs=opus' });
      chunksRef.current = [];

      recorder.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      recorder.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunksRef.current, { type: 'audio/webm;codecs=opus' });
        if (blob.size > 0) sendToWhisper(blob);
        else setState('idle');
      };

      mediaRecRef.current = recorder;
      recorder.start();
      setState('recording');
    } catch {
      // Mic permission denied — try Web Speech API which handles its own permission
      fallbackWebSpeech();
    }
  }, [sendToWhisper, fallbackWebSpeech]);

  const stopRecording = useCallback(() => {
    const rec = mediaRecRef.current;
    if (rec && rec.state === 'recording') {
      rec.stop();
      mediaRecRef.current = null;
    }
  }, []);

  const handleClick = useCallback(() => {
    if (state === 'recording') stopRecording();
    else if (state === 'idle') startRecording();
    // ignore clicks while processing
  }, [state, startRecording, stopRecording]);

  const isRecording = state === 'recording';
  const isProcessing = state === 'processing';
  const isDisabled = disabled || !activeProject || isProcessing;

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={isDisabled}
      aria-label={isRecording ? 'Stop recording' : 'Start voice input'}
      title={isRecording ? 'Stop recording' : 'Voice input'}
      className={cn(
        'p-2 rounded-xl transition-all shrink-0',
        isRecording
          ? 'bg-red-500 text-white animate-pulse'
          : isProcessing
            ? 'text-amber-400 cursor-wait'
            : isDisabled
              ? 'text-white/20 cursor-not-allowed'
              : 'text-white/40 hover:text-white/70 hover:bg-white/5',
      )}
    >
      <Mic size={16} />
    </button>
  );
};
