import React from 'react';

type LogoProps = {
  className?: string;
  variant?: 'full' | 'icon' | 'wordmark';
  size?: 'sm' | 'md' | 'lg' | 'xl';
  showSlogan?: boolean;
  layout?: 'horizontal' | 'vertical';
};

const sizes = {
  sm: { icon: 'h-6', text: 'text-xl' },
  md: { icon: 'h-8', text: 'text-2xl' },
  lg: { icon: 'h-10', text: 'text-3xl' },
  xl: { icon: 'h-16', text: 'text-5xl' },
};

export const Logo: React.FC<LogoProps> = ({ 
  className = '', 
  variant = 'full', 
  size = 'md',
  showSlogan = false,
  layout = 'horizontal'
}) => {
  const { icon: iconSize, text: textSize } = sizes[size];
  const isVertical = layout === 'vertical';

  return (
    <div className={`flex ${isVertical ? 'flex-col justify-center items-center text-center' : 'flex-row items-center'} gap-3 ${className}`}>
      {/* Icon */}
      {variant !== 'wordmark' && (
        <img 
          src="/mezan-symbol-flat.svg" 
          alt="Mezan Logo" 
          className={`${iconSize} w-auto object-contain flex-shrink-0`} 
        />
      )}
      
      {/* Wordmark and Slogan */}
      <div className={`flex flex-col ${isVertical ? 'items-center' : 'items-start justify-center'}`}>
        {variant !== 'icon' && (
          <span className={`mezan-logo-text ${textSize} leading-none mt-1`}>
            mezan
          </span>
        )}
        
        {showSlogan && (
          <span className={`mezan-slogan text-gray-500 font-medium opacity-90 ${isVertical ? 'text-base mt-2' : 'text-xs mt-1'}`}>
            نظّم مصروفاتك.. وحقق التوازن
          </span>
        )}
      </div>
    </div>
  );
};
