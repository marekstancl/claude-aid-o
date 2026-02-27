import React, { useEffect, useCallback, useState, useRef, useMemo } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { marked } from 'marked';
import DOMPurify from 'dompurify';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import {
  Archive,
  FileText,
  Search,
  ChevronRight,
  ChevronDown,
  Book,
  Folder,
  FileJson,
  FileCode,
  Hash,
  Loader2,
  Eye,
  EyeOff,
  X,
} from 'lucide-react';
import type { ApiError, EvidenceSearchResult, EvidenceSearchResponse } from '../types/api';

const client = createApiClient('default');

// ---------------------------------------------------------------------------
// Markdown rendering setup
// ---------------------------------------------------------------------------

marked.setOptions({ breaks: true, gfm: true });

function renderMarkdownToHtml(text: string): string {
  try {
    const raw = marked.parse(text) as string;
    return DOMPurify.sanitize(raw);
  } catch {
    return DOMPurify.sanitize(text);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Parse a runId timestamp like "20260227T173200Z" into a Date object.
 * Falls back to current date if parsing fails.
 */
function parseRunIdToDate(runId: string): Date {
  // Expected format: YYYYMMDDTHHmmssZ
  const match = runId.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/);
  if (match) {
    const [, year, month, day, hour, minute, second] = match;
    return new Date(
      Date.UTC(
        parseInt(year, 10),
        parseInt(month, 10) - 1,
        parseInt(day, 10),
        parseInt(hour, 10),
        parseInt(minute, 10),
        parseInt(second, 10),
      ),
    );
  }
  return new Date();
}

/**
 * Format a date as a readable string like "Feb 27, 2026".
 */
function formatDateLabel(date: Date): string {
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

/**
 * Group runs by date (YYYY-MM-DD key), sorted most recent first.
 */
function groupRunsByDate(
  runs: Array<{ runId: string; files: string[]; hasStageLog: boolean; hasPlan: boolean; hasGatesReport: boolean }>,
): Array<{ dateKey: string; dateLabel: string; runs: typeof runs }> {
  const groups = new Map<string, { dateLabel: string; runs: typeof runs }>();

  for (const run of runs) {
    const date = parseRunIdToDate(run.runId);
    const dateKey = date.toISOString().slice(0, 10);
    const dateLabel = formatDateLabel(date);

    if (!groups.has(dateKey)) {
      groups.set(dateKey, { dateLabel, runs: [] });
    }
    groups.get(dateKey)!.runs.push(run);
  }

  // Sort by dateKey descending (most recent first)
  const sorted = Array.from(groups.entries())
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([dateKey, { dateLabel, runs: groupRuns }]) => ({
      dateKey,
      dateLabel,
      runs: groupRuns,
    }));

  return sorted;
}

/**
 * Custom hook for debounced value.
 */
function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delayMs);
    return () => clearTimeout(timer);
  }, [value, delayMs]);

  return debouncedValue;
}

/**
 * Highlight matched text within a context string.
 * Returns an array of React nodes with matches wrapped in <mark>.
 */
function highlightMatch(text: string, query: string): React.ReactNode {
  if (!query.trim()) return text;
  const escapedQuery = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(`(${escapedQuery})`, 'gi');
  const parts = text.split(regex);
  return parts.map((part, i) =>
    regex.test(part) ? (
      <mark key={i} className="bg-yellow-400/30 text-yellow-200 rounded-sm px-0.5">
        {part}
      </mark>
    ) : (
      part
    ),
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Local state: search
  // ---------------------------------------------------------------------------
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<EvidenceSearchResponse | null>(null);
  const [searchLoading, setSearchLoading] = useState(false);

  // ---------------------------------------------------------------------------
  // Local state: collapsible date groups
  // ---------------------------------------------------------------------------
  const [collapsedDates, setCollapsedDates] = useState<Set<string>>(new Set());

  // ---------------------------------------------------------------------------
  // Local state: markdown preview
  // ---------------------------------------------------------------------------
  const [markdownPreview, setMarkdownPreview] = useState(false);

  // Debounce the search query at 300ms
  const debouncedQuery = useDebouncedValue(searchQuery, 300);

  // Track the latest search request to ignore stale responses
  const searchRequestRef = useRef(0);

  // ---------------------------------------------------------------------------
  // Fetch evidence tree on mount
  // ---------------------------------------------------------------------------
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
    return () => {
      cancelled = true;
    };
  }, [setEvidenceEpics, setEvidenceLoading]);

  // ---------------------------------------------------------------------------
  // Execute search when debounced query changes
  // ---------------------------------------------------------------------------
  useEffect(() => {
    if (!debouncedQuery.trim()) {
      setSearchResults(null);
      setSearchLoading(false);
      return;
    }

    const requestId = ++searchRequestRef.current;
    setSearchLoading(true);

    const doSearch = async () => {
      const result = await client.searchEvidence(debouncedQuery);
      // Ignore stale responses
      if (requestId !== searchRequestRef.current) return;
      if (result.ok) {
        setSearchResults(result.data);
      } else {
        console.error('Search failed:', (result as ApiError).error.message);
        setSearchResults(null);
      }
      setSearchLoading(false);
    };

    doSearch();
  }, [debouncedQuery]);

  // Show loading spinner in search input while typing (before debounce fires)
  // or while the request is in flight
  const isSearchActive = searchQuery.trim().length > 0;
  const isSearchInputLoading = isSearchActive && (searchQuery !== debouncedQuery || searchLoading);

  // ---------------------------------------------------------------------------
  // Initialize collapsed state: most recent date expanded, rest collapsed
  // ---------------------------------------------------------------------------
  const dateGroupsByEpic = useMemo(() => {
    const map = new Map<string, ReturnType<typeof groupRunsByDate>>();
    for (const epic of evidenceEpics) {
      map.set(epic.epicId, groupRunsByDate(epic.runs));
    }
    return map;
  }, [evidenceEpics]);

  // Set initial collapsed state when evidence data loads
  useEffect(() => {
    const initialCollapsed = new Set<string>();
    for (const [epicId, groups] of dateGroupsByEpic.entries()) {
      // Collapse all groups except the first (most recent) for each epic
      for (let i = 1; i < groups.length; i++) {
        initialCollapsed.add(`${epicId}:${groups[i].dateKey}`);
      }
    }
    setCollapsedDates(initialCollapsed);
  }, [dateGroupsByEpic]);

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  const handleFileSelect = useCallback(
    async (filePath: string) => {
      if (!selectedEvidenceEpic || !selectedEvidenceRun) return;
      setEvidenceSelection(selectedEvidenceEpic, selectedEvidenceRun, filePath);
      setMarkdownPreview(false); // Reset preview when switching files
      setEvidenceLoading(true);
      const result = await client.getEvidenceFile(selectedEvidenceEpic, selectedEvidenceRun, filePath);
      if (result.ok) {
        setEvidenceFileContent(result.data);
      } else {
        console.error('Failed to fetch evidence file:', (result as ApiError).error.message);
        setEvidenceFileContent(null);
      }
      setEvidenceLoading(false);
    },
    [selectedEvidenceEpic, selectedEvidenceRun, setEvidenceSelection, setEvidenceFileContent, setEvidenceLoading],
  );

  const handleSearchResultClick = useCallback(
    async (result: EvidenceSearchResult) => {
      // Navigate to the file from the search result
      setEvidenceSelection(result.epicId, result.runId, result.filePath);
      setSearchQuery('');
      setSearchResults(null);
      setMarkdownPreview(false);
      setEvidenceLoading(true);
      const fileResult = await client.getEvidenceFile(result.epicId, result.runId, result.filePath);
      if (fileResult.ok) {
        setEvidenceFileContent(fileResult.data);
      } else {
        console.error('Failed to fetch evidence file:', (fileResult as ApiError).error.message);
        setEvidenceFileContent(null);
      }
      setEvidenceLoading(false);
    },
    [setEvidenceSelection, setEvidenceFileContent, setEvidenceLoading],
  );

  const toggleDateGroup = useCallback((epicId: string, dateKey: string) => {
    const key = `${epicId}:${dateKey}`;
    setCollapsedDates((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }, []);

  const clearSearch = useCallback(() => {
    setSearchQuery('');
    setSearchResults(null);
    setSearchLoading(false);
  }, []);

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  const selectedEpicEntry = evidenceEpics.find((e) => e.epicId === selectedEvidenceEpic);
  const selectedRunEntry = selectedEpicEntry?.runs.find((r) => r.runId === selectedEvidenceRun);
  const files = selectedRunEntry?.files ?? [];

  const isMarkdownFile = selectedEvidenceFile?.endsWith('.md') ?? false;
  const isViewingMarkdown = evidenceFileContent?.format === 'markdown';

  // ---------------------------------------------------------------------------
  // Sub-renders
  // ---------------------------------------------------------------------------

  const getFileIcon = (fileName: string) => {
    if (fileName.endsWith('.json')) return <FileJson size={16} />;
    if (fileName.endsWith('.jsonl')) return <Hash size={16} />;
    if (fileName.endsWith('.yaml') || fileName.endsWith('.yml')) return <FileCode size={16} />;
    if (fileName.endsWith('.md')) return <FileText size={16} />;
    return <FileCode size={16} />;
  };

  const renderContent = () => {
    // If search results are showing, render them in the main area
    if (searchResults) {
      return renderSearchResults();
    }

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
            <div className="flex items-center gap-3">
              {/* Markdown preview toggle */}
              {isViewingMarkdown && (
                <button
                  onClick={() => setMarkdownPreview((prev) => !prev)}
                  className={cn(
                    'flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium transition-all border',
                    markdownPreview
                      ? 'bg-white/10 text-white border-white/20'
                      : 'bg-white/5 text-white/40 border-white/10 hover:text-white hover:bg-white/10',
                  )}
                  title={markdownPreview ? 'Show raw markdown' : 'Preview rendered markdown'}
                >
                  {markdownPreview ? <EyeOff size={14} /> : <Eye size={14} />}
                  <span>{markdownPreview ? 'Raw' : 'Preview'}</span>
                </button>
              )}
              <div className="flex gap-2">
                <div className="w-2 h-2 rounded-full bg-white/10" />
                <div className="w-2 h-2 rounded-full bg-white/10" />
                <div className="w-2 h-2 rounded-full bg-white/10" />
              </div>
            </div>
          </div>
          <div className="p-8">
            {(format === 'json' || format === 'yaml') && (
              <pre className="text-xs font-mono text-white/70 whitespace-pre-wrap overflow-x-auto">
                {typeof content === 'string' ? content : JSON.stringify(content, null, 2)}
              </pre>
            )}
            {format === 'markdown' && (
              <>
                {markdownPreview ? (
                  <div
                    className="prose prose-invert prose-sm max-w-none text-white/70 [&_a]:text-blue-400 [&_code]:bg-white/10 [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:rounded [&_pre]:bg-white/5 [&_pre]:border [&_pre]:border-white/10 [&_pre]:rounded-xl [&_h1]:text-white/90 [&_h2]:text-white/90 [&_h3]:text-white/80 [&_strong]:text-white/80 [&_li]:text-white/60 [&_blockquote]:border-white/20 [&_blockquote]:text-white/50 [&_hr]:border-white/10 [&_table]:border-white/10 [&_th]:border-white/10 [&_td]:border-white/10 [&_th]:px-3 [&_th]:py-2 [&_td]:px-3 [&_td]:py-2"
                    dangerouslySetInnerHTML={{
                      __html: renderMarkdownToHtml(typeof content === 'string' ? content : String(content)),
                    }}
                  />
                ) : (
                  <pre className="text-sm text-white/60 whitespace-pre-wrap leading-relaxed">
                    {typeof content === 'string' ? content : String(content)}
                  </pre>
                )}
              </>
            )}
            {format === 'jsonl' && (
              <div className="space-y-3">
                {(Array.isArray(content) ? content : []).map((line, i) => (
                  <div key={i} className="flex gap-4 items-start border-l-2 border-white/10 pl-4 py-1">
                    <span className="text-[10px] font-mono text-white/20 shrink-0 mt-0.5">
                      {String(i + 1).padStart(3, '0')}
                    </span>
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

  const renderSearchResults = () => {
    if (!searchResults) return null;

    return (
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <Search size={16} className="text-white/40" />
            <span className="text-sm text-white/60">
              {searchResults.total} result{searchResults.total !== 1 ? 's' : ''} for{' '}
              <span className="text-white font-medium">"{searchResults.query}"</span>
            </span>
          </div>
          <button
            onClick={clearSearch}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg text-xs font-medium transition-all"
          >
            <X size={12} />
            Clear search
          </button>
        </div>

        {searchResults.results.length === 0 ? (
          <div className="flex items-center justify-center py-16 text-white/20">
            <div className="text-center space-y-4">
              <Search size={48} className="mx-auto" />
              <p className="text-sm">No matches found</p>
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            {searchResults.results.map((result, i) => (
              <button
                key={`${result.epicId}-${result.runId}-${result.filePath}-${result.matchLine}-${i}`}
                onClick={() => handleSearchResultClick(result)}
                className="w-full text-left glass rounded-xl border border-white/10 p-4 hover:bg-white/5 transition-all group"
              >
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-[10px] font-bold uppercase tracking-widest text-white/30">
                    EPIC {result.epicId}
                  </span>
                  <ChevronRight size={10} className="text-white/20" />
                  <span className="text-[10px] font-mono text-white/30">{result.runId}</span>
                  <ChevronRight size={10} className="text-white/20" />
                  <span className="text-xs font-mono text-white/50 group-hover:text-white/70 transition-colors">
                    {result.filePath}
                  </span>
                </div>
                <div className="flex items-start gap-3">
                  <span className="text-[10px] font-mono text-white/20 mt-0.5 shrink-0">
                    L{result.matchLine}
                  </span>
                  <pre className="text-xs font-mono text-white/50 whitespace-pre-wrap overflow-hidden">
                    {highlightMatch(result.context, searchResults.query)}
                  </pre>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>
    );
  };

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="h-full flex overflow-hidden">
      {/* Left Panel - Volumes */}
      <aside className="w-72 border-r border-white/5 flex flex-col bg-surface-1/30">
        <div className="p-6 border-b border-white/5">
          <h2 className="text-xl font-bold tracking-tight mb-4">Evidence Vault</h2>
          <div className="relative">
            {isSearchInputLoading ? (
              <Loader2
                size={14}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-white/40 animate-spin"
              />
            ) : (
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-white/20" />
            )}
            <input
              type="text"
              placeholder="Search evidence..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full bg-white/5 border border-white/10 rounded-lg py-2 pl-9 pr-8 text-xs focus:outline-none focus:border-white/20"
            />
            {searchQuery && (
              <button
                onClick={clearSearch}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-white/20 hover:text-white/50 transition-colors"
              >
                <X size={12} />
              </button>
            )}
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
            evidenceEpics.map((epic) => {
              const dateGroups = dateGroupsByEpic.get(epic.epicId) ?? [];

              return (
                <div key={epic.epicId} className="space-y-2">
                  <div className="flex items-center gap-2 px-2 text-[10px] font-bold uppercase tracking-widest text-white/40">
                    <Book size={12} />
                    <span>EPIC {epic.epicId}</span>
                  </div>

                  <div className="space-y-1">
                    {dateGroups.map((group) => {
                      const groupKey = `${epic.epicId}:${group.dateKey}`;
                      const isCollapsed = collapsedDates.has(groupKey);

                      return (
                        <div key={group.dateKey}>
                          {/* Date group header */}
                          <button
                            onClick={() => toggleDateGroup(epic.epicId, group.dateKey)}
                            className="w-full flex items-center gap-2 px-3 py-1.5 text-[11px] font-semibold text-white/30 hover:text-white/50 transition-colors"
                          >
                            <motion.div
                              animate={{ rotate: isCollapsed ? -90 : 0 }}
                              transition={{ duration: 0.15 }}
                            >
                              <ChevronDown size={12} />
                            </motion.div>
                            <span>{group.dateLabel}</span>
                            <span className="text-[10px] text-white/20 font-normal">
                              ({group.runs.length})
                            </span>
                          </button>

                          {/* Collapsible run list */}
                          <AnimatePresence initial={false}>
                            {!isCollapsed && (
                              <motion.div
                                initial={{ height: 0, opacity: 0 }}
                                animate={{ height: 'auto', opacity: 1 }}
                                exit={{ height: 0, opacity: 0 }}
                                transition={{ duration: 0.2, ease: 'easeInOut' }}
                                className="overflow-hidden"
                              >
                                <div className="space-y-1 pl-2">
                                  {group.runs.map((run) => (
                                    <button
                                      key={run.runId}
                                      onClick={() => {
                                        setEvidenceSelection(epic.epicId, run.runId, null);
                                        setEvidenceFileContent(null);
                                        setMarkdownPreview(false);
                                      }}
                                      className={cn(
                                        'w-full flex items-center justify-between px-3 py-2 rounded-xl text-sm transition-all',
                                        selectedEvidenceEpic === epic.epicId &&
                                          selectedEvidenceRun === run.runId
                                          ? 'bg-white/10 text-white shadow-sm'
                                          : 'text-white/40 hover:text-white hover:bg-white/5',
                                      )}
                                    >
                                      <div className="flex items-center gap-2">
                                        <Folder
                                          size={14}
                                          className={
                                            selectedEvidenceEpic === epic.epicId &&
                                            selectedEvidenceRun === run.runId
                                              ? 'text-state-executing'
                                              : ''
                                          }
                                        />
                                        <span className="text-xs">{run.runId}</span>
                                      </div>
                                      {selectedEvidenceEpic === epic.epicId &&
                                        selectedEvidenceRun === run.runId && <ChevronRight size={14} />}
                                    </button>
                                  ))}
                                </div>
                              </motion.div>
                            )}
                          </AnimatePresence>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })
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
          {/* File List — hidden when search results are showing */}
          {!searchResults && (
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
              {files.map((fileName) => (
                <button
                  key={fileName}
                  onClick={() => handleFileSelect(fileName)}
                  className={cn(
                    'w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left transition-all group',
                    selectedEvidenceFile === fileName ? 'bg-white/10 text-white' : 'hover:bg-white/5',
                  )}
                >
                  <div
                    className={cn(
                      'p-2 rounded-lg bg-white/5 transition-colors',
                      selectedEvidenceFile === fileName
                        ? 'text-white'
                        : 'text-white/40 group-hover:text-white',
                    )}
                  >
                    {getFileIcon(fileName)}
                  </div>
                  <div className="min-w-0">
                    <div className="text-xs font-medium truncate">{fileName}</div>
                  </div>
                </button>
              ))}
            </div>
          )}

          {/* Content Viewer */}
          <div className="flex-1 p-8 overflow-y-auto">{renderContent()}</div>
        </div>
      </main>
    </div>
  );
};
