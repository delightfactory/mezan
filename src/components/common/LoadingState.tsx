import React from 'react';
import { Logo } from './Logo';

export const LoadingState: React.FC = () => {
  return (
    <div className="flex h-64 flex-col items-center justify-center space-y-4">
      <Logo variant="icon" size="lg" className="animate-pulse" />
      <p className="animate-pulse text-sm font-bold text-gray-400">جاري التحميل...</p>
    </div>
  );
};
