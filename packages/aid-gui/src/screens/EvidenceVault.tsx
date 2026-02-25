import React, { useState } from 'react';
import { motion } from 'motion/react';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { Archive, FileText, Search, ChevronRight, Book, Folder, FileJson, FileCode, Hash } from 'lucide-react';

export const EvidenceVault: React.FC = () => {
  const [selectedEpic, setSelectedEpic] = useState('E-005');
  const [selectedRun, setSelectedRun] = useState('Run 1');

  const epics = [
    { id: 'E-005', name: 'Auth System Refactor', runs: ['Run 1', 'Run 2'] },
    { id: 'E-004', name: 'Dashboard UI', runs: ['Run 1'] },
    { id: 'E-003', name: 'API V2 Migration', runs: ['Run 1', 'Run 2', 'Run 3'] },
  ];

  const files = [
    { name: 'plan.json', type: 'json', size: '12kb' },
    { name: 'stage_log.jsonl', type: 'jsonl', size: '450kb' },
    { name: 'agent_output.md', type: 'md', size: '24kb' },
    { name: 'changes.patch', type: 'diff', size: '1.2mb' },
    { name: 'audit_report.yaml', type: 'yaml', size: '8kb' },
  ];

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
          {epics.map(epic => (
            <div key={epic.id} className="space-y-2">
              <div className="flex items-center gap-2 px-2 text-[10px] font-bold uppercase tracking-widest text-white/40">
                <Book size={12} />
                <span>EPIC {epic.id}</span>
              </div>
              <div className="space-y-1">
                {epic.runs.map(run => (
                  <button
                    key={run}
                    onClick={() => {
                      setSelectedEpic(epic.id);
                      setSelectedRun(run);
                    }}
                    className={cn(
                      "w-full flex items-center justify-between px-3 py-2 rounded-xl text-sm transition-all",
                      selectedEpic === epic.id && selectedRun === run 
                        ? "bg-white/10 text-white shadow-sm" 
                        : "text-white/40 hover:text-white hover:bg-white/5"
                    )}
                  >
                    <div className="flex items-center gap-2">
                      <Folder size={14} className={selectedEpic === epic.id && selectedRun === run ? "text-state-executing" : ""} />
                      <span>{run}</span>
                    </div>
                    {selectedEpic === epic.id && selectedRun === run && <ChevronRight size={14} />}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col bg-bg-base/40">
        <div className="h-14 border-b border-white/5 flex items-center justify-between px-6">
          <div className="flex items-center gap-2 text-sm">
            <span className="text-white/40">Evidence</span>
            <ChevronRight size={14} className="text-white/20" />
            <span className="text-white/40">EPIC {selectedEpic}</span>
            <ChevronRight size={14} className="text-white/20" />
            <span className="font-medium">{selectedRun}</span>
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
            {files.map(file => (
              <button
                key={file.name}
                className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left hover:bg-white/5 transition-all group"
              >
                <div className="p-2 rounded-lg bg-white/5 text-white/40 group-hover:text-white transition-colors">
                  {file.type === 'json' || file.type === 'jsonl' ? <FileJson size={16} /> :
                   file.type === 'md' ? <FileText size={16} /> :
                   file.type === 'diff' ? <Hash size={16} /> :
                   <FileCode size={16} />}
                </div>
                <div className="min-w-0">
                  <div className="text-xs font-medium truncate">{file.name}</div>
                  <div className="text-[10px] text-white/20 uppercase tracking-widest">{file.size}</div>
                </div>
              </button>
            ))}
          </div>

          {/* Content Viewer */}
          <div className="flex-1 p-8 overflow-y-auto">
            <div className="max-w-4xl mx-auto">
              <div className="glass rounded-2xl border border-white/10 overflow-hidden">
                <div className="bg-white/5 px-6 py-3 border-b border-white/10 flex items-center justify-between">
                  <span className="text-xs font-mono text-white/40">agent_output.md</span>
                  <div className="flex gap-2">
                    <div className="w-2 h-2 rounded-full bg-white/10" />
                    <div className="w-2 h-2 rounded-full bg-white/10" />
                    <div className="w-2 h-2 rounded-full bg-white/10" />
                  </div>
                </div>
                <div className="p-8 prose prose-invert prose-sm max-w-none">
                  <h1 className="text-2xl font-bold mb-4">Implementation Summary</h1>
                  <p className="text-white/60 mb-6">
                    I have successfully refactored the authentication system to use the new permission-sandwich pattern. 
                    This change improves security by enforcing checks at both the API gateway and the service layer.
                  </p>
                  <h2 className="text-lg font-bold mb-3">Key Changes</h2>
                  <ul className="list-disc list-inside text-white/60 space-y-2 mb-6">
                    <li>Updated <code>auth-service.ts</code> to handle JWT validation</li>
                    <li>Implemented <code>PermissionGuard</code> middleware</li>
                    <li>Added 12 new unit tests for edge cases</li>
                  </ul>
                  <div className="bg-black/40 rounded-xl p-4 font-mono text-xs border border-white/5">
                    <span className="text-state-executing">const</span> auth = <span className="text-state-pm-approval">await</span> verifyToken(token);
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};
