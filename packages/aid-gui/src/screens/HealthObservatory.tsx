import React, { useState } from 'react';
import { motion } from 'motion/react';
import { useStore } from '../store';
import { cn } from '../lib/utils';
import { HeartPulse, Shield, FileText, Layout, Database, AlertTriangle, Info, CheckCircle2, TrendingUp } from 'lucide-react';
import { ResponsiveContainer, PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, Tooltip } from 'recharts';

export const HealthObservatory: React.FC = () => {
  const healthScore = 92;
  
  const categories = [
    { name: 'Code Quality', score: 94, color: '#22c55e', icon: FileText },
    { name: 'Security', score: 88, color: '#eab308', icon: Shield },
    { name: 'Architecture', score: 96, color: '#00b4d8', icon: Database },
    { name: 'Testing', score: 90, color: '#7c5cbf', icon: CheckCircle2 },
  ];

  const findings = [
    { id: 'f1', severity: 'warning', category: 'Security', title: 'Sensitive data in logs', description: 'Potential leak of API keys in debug logs of auth-service.', file: 'src/services/auth.ts' },
    { id: 'f2', severity: 'info', category: 'Code Quality', title: 'Complex function detected', description: 'The handleRequest function in api-gateway has a cyclomatic complexity of 15.', file: 'src/gateway.ts' },
    { id: 'f3', severity: 'critical', category: 'Testing', title: 'Missing test coverage', description: 'New payment module has 0% branch coverage.', file: 'src/modules/payment.ts' },
  ];

  return (
    <div className="h-full flex flex-col p-8 overflow-y-auto custom-scrollbar">
      <div className="flex items-center justify-between mb-12">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Health Observatory</h2>
          <p className="text-sm text-white/40">Project audit and quality metrics</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex flex-col items-end">
            <div className="text-[10px] font-bold uppercase tracking-widest text-white/40">Overall Score</div>
            <div className="text-3xl font-bold text-state-done">{healthScore}</div>
          </div>
          <div className="w-12 h-12 rounded-full border-4 border-state-done/20 border-t-state-done animate-spin-slow" />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 mb-12">
        {/* Central Gauge Area */}
        <div className="lg:col-span-2 glass p-8 rounded-[2.5rem] flex items-center justify-around relative overflow-hidden">
          <div className="absolute top-0 left-0 w-full h-full bg-gradient-to-br from-state-done/5 to-transparent pointer-events-none" />
          
          <div className="relative w-64 h-64">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={[{ value: healthScore }, { value: 100 - healthScore }]}
                  innerRadius={80}
                  outerRadius={100}
                  startAngle={90}
                  endAngle={450}
                  dataKey="value"
                  stroke="none"
                >
                  <Cell fill="var(--color-state-done)" />
                  <Cell fill="rgba(255,255,255,0.05)" />
                </Pie>
              </PieChart>
            </ResponsiveContainer>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-5xl font-bold tracking-tighter bg-gradient-to-b from-white to-state-done bg-clip-text text-transparent">{healthScore}</span>
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">Optimal</span>
            </div>
          </div>

          <div className="space-y-6 flex-1 max-w-xs">
            {categories.map(cat => (
              <div key={cat.name} className="space-y-2">
                <div className="flex justify-between text-xs">
                  <div className="flex items-center gap-2 text-white/60">
                    <cat.icon size={14} />
                    <span>{cat.name}</span>
                  </div>
                  <span className="font-mono">{cat.score}%</span>
                </div>
                <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
                  <motion.div 
                    initial={{ width: 0 }}
                    animate={{ width: `${cat.score}%` }}
                    className="h-full rounded-full"
                    style={{ backgroundColor: cat.color }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Trend Sparkline */}
        <div className="glass p-8 rounded-[2.5rem] flex flex-col justify-between">
          <div>
            <div className="flex items-center gap-2 text-state-executing mb-1">
              <TrendingUp size={16} />
              <span className="text-[10px] font-bold uppercase tracking-widest">Health Trend</span>
            </div>
            <h3 className="text-xl font-bold">+4.2% this week</h3>
          </div>
          <div className="h-32 w-full mt-4">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={[
                { day: 'M', score: 82 },
                { day: 'T', score: 85 },
                { day: 'W', score: 84 },
                { day: 'T', score: 88 },
                { day: 'F', score: 90 },
                { day: 'S', score: 92 },
                { day: 'S', score: 92 },
              ]}>
                <Bar dataKey="score" fill="var(--color-state-executing)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <h3 className="text-lg font-bold tracking-tight mb-6">Critical Findings</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {findings.map(finding => (
            <motion.div
              key={finding.id}
              whileHover={{ y: -4 }}
              className={cn(
                "glass p-6 rounded-2xl border-l-4 transition-all",
                finding.severity === 'critical' ? "border-l-state-error" :
                finding.severity === 'warning' ? "border-l-state-pm-approval" :
                "border-l-state-executing"
              )}
            >
              <div className="flex items-center justify-between mb-4">
                <div className="px-2 py-0.5 rounded bg-white/5 text-[10px] font-bold uppercase tracking-widest text-white/40">
                  {finding.category}
                </div>
                {finding.severity === 'critical' ? <AlertTriangle size={16} className="text-state-error" /> : <Info size={16} className="text-white/20" />}
              </div>
              <h4 className="font-bold mb-2">{finding.title}</h4>
              <p className="text-xs text-white/60 leading-relaxed mb-4">{finding.description}</p>
              <div className="text-[10px] font-mono text-white/40 truncate bg-white/5 p-2 rounded">
                {finding.file}
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
};
