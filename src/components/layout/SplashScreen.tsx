import React from 'react';
import { Logo } from '../common/Logo';

export const SplashScreen: React.FC = () => {
  return (
    <div className="flex h-screen w-full flex-col items-center justify-center bg-mezan-surface">
      <div className="flex flex-col items-center animate-fade-in-up">
        {/* We can use the icon or full logo here, let's use the icon then the wordmark */}
        <Logo variant="icon" size="xl" className="mb-6 animate-pulse-slow" />
        <Logo variant="wordmark" size="lg" showSlogan layout="vertical" />
      </div>
      
      {/* Loading Indicator */}
      <div className="absolute bottom-12 flex flex-col items-center gap-3">
        <div className="h-1.5 w-24 overflow-hidden rounded-full bg-gray-200">
          <div className="h-full bg-mezan-primary animate-progress rounded-full"></div>
        </div>
      </div>
    </div>
  );
};
