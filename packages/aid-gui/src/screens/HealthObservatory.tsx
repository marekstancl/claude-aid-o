import React, { useEffect } from 'react';
import { motion } from 'motion/react';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import { cn } from '../lib/utils';
import { HeartPulse, Shield, FileText, Layout, Database, AlertTriangle, Info, CheckCircle2, TrendingUp } from 'lucide-react';
import { ResponsiveContainer, PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, Tooltip } from 'recharts';
import type { ApiError, AuditFinding } from '../types/api';

const client = createApiClient('default');

export const HealthObservatory: React.FC = () => {
  const auditReports = useStore((s) => s.auditReports);
  const latestAudit = useStore((s) => s.latestAudit);
  const auditLoading = useStore((s) => s.auditLoading);
  const setAuditReports = useStore((s) => s.setAuditReports);
  const setAuditLoading = useStore((s) => s.setAuditLoading);

  // Fetch audit data on mount
  useEffect(() => {
    let cancelled = false;
    const fetchAudit = async () => {
      setAuditLoading(true);
      const result = await client.getAuditHealth();
      if (cancelled) return;
      if (result.ok) {
        setAuditReports([result.data]);
      } else {
        console.error('Failed to fetch audit data:', (result as ApiError).error.message);
      }
      setAuditLoading(false);
    };
    fetchAudit();
    return () => { cancelled = true; };
  }, [setAuditReports, setAuditLoading]);

  // If loading, show loading state
  if (auditLoading && !latestAudit) {
    return (
      <div className="h-full flex flex-col p-8 items-center justify-center">
        <div className="w-16 h-16 rounded-full border-4 border-white/10 border-t-white/40 animate-spin mb-6" />
        <p className="text-sm text-white/40">Loading audit data...</p>
      </div>
    );
  }

  // If no audit data, show empty state
  if (!latestAudit) {
    return (
      <div className="h-full flex flex-col p-8 items-center justify-center">
        <HeartPulse size={48} className="text-white/20 mb-4" />
        <h3 className="text-xl font-medium text-white/40 mb-2">No audit data available</h3>
        <p className="text-sm text-white/20">Run an audit to see project health metrics.</p>
      </div>
    );
  }

  const healthScore = latestAudit.scores.overall;

  // Map real scores to the display categories
  const categories = [
    {
      name: 'Code Quality',
      score: latestAudit.scores.codeQuality ?? 0,
      color: '#22c55e',
      icon: FileText,
    },
    {
      name: 'Security',
      score: latestAudit.scores.security ?? 0,
      color: '#eab308',
      icon: Shield,
    },
    {
      name: 'Architecture',
      score: latestAudit.scores.documentation ?? 0,
      color: '#00b4d8',
      icon: Database,
    },
    {
      name: 'Testing',
      score: latestAudit.scores.process ?? 0,
      color: '#7c5cbf',
      icon: CheckCircle2,
    },
  ];

  // Compute score label
  const getScoreLabel = (score: number): string => {
    if (score >= 90) return 'Optimal';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Work';
  };

  // Build trend display
  const trend = latestAudit.trend;
  const hasTrendData = trend && trend.scoreDelta !== null;
  const trendDelta = hasTrendData ? trend.scoreDelta! : 0;
  const trendSign = trendDelta >= 0 ? '+' : '';
  const trendLabel = hasTrendData
    ? `${trendSign}${trendDelta.toFixed(1)}% ${trend.direction ?? ''}`
    : 'Insufficient data';

  // Severity color mapping for findings
  const getSeverityBorderClass = (severity: AuditFinding['severity']): string => {
    switch (severity) {
      case 'critical': return 'border-l-red-500';
      case 'high': return 'border-l-orange-500';
      case 'medium': return 'border-l-yellow-500';
      case 'low': return 'border-l-blue-500';
      default: return 'border-l-white/20';
    }
  };

  const getSeverityIconColor = (severity: AuditFinding['severity']): string => {
    switch (severity) {
      case 'critical': return 'text-red-500';
      case 'high': return 'text-orange-500';
      case 'medium': return 'text-yellow-500';
      case 'low': return 'text-blue-500';
      default: return 'text-white/20';
    }
  };

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
              <span className="text-[10px] font-bold uppercase tracking-widest text-white/40">{getScoreLabel(healthScore)}</span>
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
            <h3 className="text-xl font-bold">{trendLabel}</h3>
          </div>
          <div className="h-32 w-full mt-4">
            {hasTrendData ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={[
                  { label: 'Previous', score: trend.previousScore ?? 0 },
                  { label: 'Current', score: healthScore },
                ]}>
                  <XAxis dataKey="label" tick={{ fontSize: 10, fill: 'rgba(255,255,255,0.4)' }} axisLine={false} tickLine={false} />
                  <Bar dataKey="score" fill="var(--color-state-executing)" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-full flex items-center justify-center text-white/20">
                <p className="text-xs">Insufficient data for trend chart</p>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <h3 className="text-lg font-bold tracking-tight mb-6">Critical Findings</h3>
        {latestAudit.findings.length === 0 ? (
          <div className="text-center py-12 text-white/30">
            <CheckCircle2 size={32} className="mx-auto mb-3" />
            <p className="text-sm">No findings reported. Project health is clean.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {latestAudit.findings.map((finding, index) => (
              <motion.div
                key={`${finding.category}-${finding.severity}-${index}`}
                whileHover={{ y: -4 }}
                className={cn(
                  "glass p-6 rounded-2xl border-l-4 transition-all",
                  getSeverityBorderClass(finding.severity)
                )}
              >
                <div className="flex items-center justify-between mb-4">
                  <div className="px-2 py-0.5 rounded bg-white/5 text-[10px] font-bold uppercase tracking-widest text-white/40">
                    {finding.category}
                  </div>
                  {finding.severity === 'critical' || finding.severity === 'high' ? (
                    <AlertTriangle size={16} className={getSeverityIconColor(finding.severity)} />
                  ) : (
                    <Info size={16} className={getSeverityIconColor(finding.severity)} />
                  )}
                </div>
                <h4 className="font-bold mb-2 capitalize">{finding.severity}</h4>
                <p className="text-xs text-white/60 leading-relaxed mb-4">{finding.description}</p>
                {finding.filePath && (
                  <div className="text-[10px] font-mono text-white/40 truncate bg-white/5 p-2 rounded">
                    {finding.filePath}
                  </div>
                )}
                {!finding.filePath && finding.recommendation && (
                  <div className="text-[10px] text-white/40 truncate bg-white/5 p-2 rounded">
                    {finding.recommendation}
                  </div>
                )}
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
