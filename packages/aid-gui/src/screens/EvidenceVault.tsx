import React, { useEffect, useCallback } from 'react';
import { motion } from 'motion/react';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import { Archive, FileText, Search, ChevronRight, Book, Folder, FileJson, FileCode, Hash } from 'lucide-react';
import type { ApiError } from '../types/api';

const client = createApiClient('default');

export const EvidenceVault: React.FC = () => {
  const evidenceEpics = useStore((s) => s.evidenceEpics);
  const selectedEvidenceEpic = useStore((s) => s.selectedEvidenceEpic);
  const selectedEvidenceRun = useStore((s) => s.selectedEvidenceRun);
  const selectedEvidenceFile = useStore((s) => s.selectedEvidenceFile);
  const evidenceFileContent = useStore((s) => s.evidenceFileContent);
  const evidenceLoading = useStore((s) => s.evidenceLoading);
  const setEvidenceEpics = useStore((s) => s.setEvidenceEpics);
  const setEvidenceSelection = useStore((s) => s.setEvidenceSelection);
  const setEvidenceFileContent = useStore((s) => s.setEvidenceFileContent);
  const setEvidenceLoading = useStore((s) => s.setEvidenceLoading);

  // Fetch evidence tree on mount
  useEffect(() => {
    let cancelled = false;
    const fetchEvidence = async () => {
      setEvidenceLoading(true);
      const result = await client.getEvidence();
      if (cancelled) return;
      if (result.ok) {
        setEvidenceEpics(result.data);
      } else {
        console.error('Failed to fetch evidence:', (result as ApiError).error.message);
      }
      setEvidenceLoading(false);
    };
    fetchEvidence();
    return () => { cancelled = true; };
  }, [setEvidenceEpics, setEvidenceLoading]);

  // Fetch file content when a file is selected
  const handleFileSelect = useCallback(async (filePath: string) => {
    if (!selectedEvidenceEpic || !selectedEvidenceRun) return;
    setEvidenceSelection(selectedEvidenceEpic, selectedEvidenceRun, filePath);
    setEvidenceLoading(true);
    const result = await client.getEvidenceFile(selectedEvidenceEpic, selectedEvidenceRun, filePath);
    if (result.ok) {
      setEvidenceFileContent(result.data);
    } else {
      console.error('Failed to fetch evidence file:', (result as ApiError).error.message);
      setEvidenceFileContent(null);
    }
    setEvidenceLoading(false);
  }, [selectedEvidenceEpic, selectedEvidenceRun, setEvidenceSelection, setEvidenceFileContent, setEvidenceLoading]);

  // Derive the selected run's file list
  const selectedEpicEntry = evidenceEpics.find((e) => e.epicId === selectedEvidenceEpic);
  const selectedRunEntry = selectedEpicEntry?.runs.find((r) => r.runId === selectedEvidenceRun);
  const files = selectedRunEntry?.files ?? [];

  // Determine file icon based on extension
  const getFileIcon = (fileName: string) => {
    if (fileName.endsWith('.json')) return <FileJson size={16} />;
    if (fileName.endsWith('.jsonl')) return <Hash size={16} />;
    if (fileName.endsWith('.yaml') || fileName.endsWith('.yml')) return <FileCode size={16} />;
    if (fileName.endsWith('.md')) return <FileText size={16} />;
    return <FileCode size={16} />;
  };

  // Render file content based on format
  const renderContent = () => {
    if (evidenceLoading && selectedEvidenceFile) {
      return (
        <div className="flex items-center justify-center h-full text-white/40">
          <div className="text-center space-y-4">
            <div className="w-12 h-12 rounded-full border-4 border-white/10 border-t-white/40 animate-spin mx-auto" />
            <p className="text-sm">Loading file...</p>
          </div>
        </div>
      );
    }

    if (!evidenceFileContent) {
      return (
        <div className="flex items-center justify-center h-full text-white/20">
          <div className="text-center space-y-4">
            <Archive size={48} className="mx-auto" />
            <p className="text-sm">Select a file to view its contents</p>
          </div>
        </div>
      );
    }

    const { format, content, filePath } = evidenceFileContent;

    return (
      <div className="max-w-4xl mx-auto">
        <div className="glass rounded-2xl border border-white/10 overflow-hidden">
          <div className="bg-white/5 px-6 py-3 border-b border-white/10 flex items-center justify-between">
            <span className="text-xs font-mono text-white/40">{filePath}</span>
            <div className="flex gap-2">
              <div className="w-2 h-2 rounded-full bg-white/10" />
              <div className="w-2 h-2 rounded-full bg-white/10" />
              <div className="w-2 h-2 rounded-full bg-white/10" />
            </div>
          </div>
          <div className="p-8">
            {(format === 'json' || format === 'yaml') && (
              <pre className="text-xs font-mono text-white/70 whitespace-pre-wrap overflow-x-auto">
                {typeof content === 'string' ? content : JSON.stringify(content, null, 2)}
              </pre>
            )}
            {format === 'markdown' && (
              <pre className="text-sm text-white/60 whitespace-pre-wrap leading-relaxed">
                {typeof content === 'string' ? content : String(content)}
              </pre>
            )}
            {format === 'jsonl' && (
              <div className="space-y-3">
                {(Array.isArray(content) ? content : []).map((line, i) => (
                  <div key={i} className="flex gap-4 items-start border-l-2 border-white/10 pl-4 py-1">
                    <span className="text-[10px] font-mono text-white/20 shrink-0 mt-0.5">{String(i + 1).padStart(3, '0')}</span>
                    <pre className="text-xs font-mono text-white/60 whitespace-pre-wrap overflow-x-auto">
                      {typeof line === 'string' ? line : JSON.stringify(line, null, 2)}
                    </pre>
                  </div>
                ))}
                {(!Array.isArray(content) || content.length === 0) && (
                  <p className="text-xs text-white/40">No entries found.</p>
                )}
              </div>
            )}
            {(format === 'text' || format === 'raw') && (
              <pre className="text-xs font-mono text-white/60 whitespace-pre-wrap overflow-x-auto">
                {typeof content === 'string' ? content : String(content)}
              </pre>
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="h-full flex overflow-hidden">
      {/* Left Panel - Volumes */}
      <aside className="w-72 border-r border-white/5 flex flex-col bg-surface-1/30">
        <div className="p-6 border-b border-white/5">
          <h2 className="text-xl font-bold tracking-tight mb-4">Evidence Vault</h2>
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-white/20" />
            <input
              type="text"
              placeholder="Search evidence..."
              className="w-full bg-white/5 border border-white/10 rounded-lg py-2 pl-9 pr-3 text-xs focus:outline-none focus:border-white/20"
            />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-6">
          {evidenceLoading && evidenceEpics.length === 0 ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-8 h-8 rounded-full border-2 border-white/10 border-t-white/40 animate-spin" />
            </div>
          ) : evidenceEpics.length === 0 ? (
            <div className="text-center py-12 text-white/30">
              <Archive size={32} className="mx-auto mb-3" />
              <p className="text-xs">No evidence data available</p>
            </div>
          ) : (
            evidenceEpics.map(epic => (
              <div key={epic.epicId} className="space-y-2">
                <div className="flex items-center gap-2 px-2 text-[10px] font-bold uppercase tracking-widest text-white/40">
                  <Book size={12} />
                  <span>EPIC {epic.epicId}</span>
                </div>
                <div className="space-y-1">
                  {epic.runs.map(run => (
                    <button
                      key={run.runId}
                      onClick={() => {
                        setEvidenceSelection(epic.epicId, run.runId, null);
                        setEvidenceFileContent(null);
                      }}
                      className={cn(
                        "w-full flex items-center justify-between px-3 py-2 rounded-xl text-sm transition-all",
                        selectedEvidenceEpic === epic.epicId && selectedEvidenceRun === run.runId
                          ? "bg-white/10 text-white shadow-sm"
                          : "text-white/40 hover:text-white hover:bg-white/5"
                      )}
                    >
                      <div className="flex items-center gap-2">
                        <Folder size={14} className={selectedEvidenceEpic === epic.epicId && selectedEvidenceRun === run.runId ? "text-state-executing" : ""} />
                        <span>{run.runId}</span>
                      </div>
                      {selectedEvidenceEpic === epic.epicId && selectedEvidenceRun === run.runId && <ChevronRight size={14} />}
                    </button>
                  ))}
                </div>
              </div>
            ))
          )}
        </div>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col bg-bg-base/40">
        <div className="h-14 border-b border-white/5 flex items-center justify-between px-6">
          <div className="flex items-center gap-2 text-sm">
            <span className="text-white/40">Evidence</span>
            {selectedEvidenceEpic && (
              <>
                <ChevronRight size={14} className="text-white/20" />
                <span className="text-white/40">EPIC {selectedEvidenceEpic}</span>
              </>
            )}
            {selectedEvidenceRun && (
              <>
                <ChevronRight size={14} className="text-white/20" />
                <span className="font-medium">{selectedEvidenceRun}</span>
              </>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button className="px-3 py-1.5 bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg text-xs font-medium transition-all">
              Download Archive
            </button>
          </div>
        </div>

        <div className="flex-1 flex">
          {/* File List */}
          <div className="w-64 border-r border-white/5 p-4 space-y-1 overflow-y-auto">
            {files.length === 0 && selectedEvidenceRun && (
              <div className="text-center py-8 text-white/30">
                <p className="text-xs">No files in this run</p>
              </div>
            )}
            {!selectedEvidenceRun && (
              <div className="text-center py-8 text-white/30">
                <p className="text-xs">Select a run to view files</p>
              </div>
            )}
            {files.map(fileName => (
              <button
                key={fileName}
                onClick={() => handleFileSelect(fileName)}
                className={cn(
                  "w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left transition-all group",
                  selectedEvidenceFile === fileName
                    ? "bg-white/10 text-white"
                    : "hover:bg-white/5"
                )}
              >
                <div className={cn(
                  "p-2 rounded-lg bg-white/5 transition-colors",
                  selectedEvidenceFile === fileName
                    ? "text-white"
                    : "text-white/40 group-hover:text-white"
                )}>
                  {getFileIcon(fileName)}
                </div>
                <div className="min-w-0">
                  <div className="text-xs font-medium truncate">{fileName}</div>
                </div>
              </button>
            ))}
          </div>

          {/* Content Viewer */}
          <div className="flex-1 p-8 overflow-y-auto">
            {renderContent()}
          </div>
        </div>
      </main>
    </div>
  );
};
