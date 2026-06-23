import React from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { cn } from '../lib/utils';

interface ErrorBoundaryProps {
  children: React.ReactNode;
  onRetry?: () => void;
  fallback?: React.ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: unknown) {
    console.error('[ErrorBoundary] Caught error:', error, errorInfo);
  }

  handleRetry = () => {
    if (this.props.onRetry) {
      this.props.onRetry();
    }
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      const isDev = typeof process !== 'undefined'
        ? process.env.NODE_ENV !== 'production'
        : true;

      return (
        <div className="flex items-center justify-center h-full p-8">
          <div
            className={cn(
              'bg-surface-2 rounded-2xl border border-white/10 p-8 max-w-lg w-full',
              'flex flex-col items-center text-center gap-4'
            )}
          >
            <div className="w-12 h-12 rounded-xl bg-red-500/10 flex items-center justify-center">
              <AlertTriangle className="w-6 h-6 text-red-400" />
            </div>

            <div className="space-y-2">
              <h2 className="text-lg font-semibold text-white/90">
                Something went wrong
              </h2>
              <p className="text-sm text-white/60">
                {this.state.error?.message || 'An unexpected error occurred while rendering this view.'}
              </p>
            </div>

            {isDev && this.state.error?.stack && (
              <pre
                className={cn(
                  'w-full text-left text-xs text-white/40 bg-white/5 rounded-xl p-4',
                  'overflow-x-auto max-h-48 overflow-y-auto border border-white/5'
                )}
              >
                {this.state.error.stack}
              </pre>
            )}

            <button
              onClick={this.handleRetry}
              className={cn(
                'flex items-center gap-2 px-4 py-2 rounded-xl',
                'bg-white/5 hover:bg-white/10 border border-white/10',
                'text-sm text-white/80 hover:text-white transition-colors'
              )}
            >
              <RefreshCw className="w-4 h-4" />
              Retry
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
