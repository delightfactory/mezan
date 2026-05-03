import React from 'react';
import { LucideIcon } from 'lucide-react';
import { Link } from 'react-router-dom';

interface EmptyStateProps {
  icon: LucideIcon;
  title: string;
  description: string;
  actionLabel?: string;
  actionLink?: string;
}

export const EmptyState: React.FC<EmptyStateProps> = ({ 
  icon: Icon, 
  title, 
  description, 
  actionLabel, 
  actionLink 
}) => {
  return (
    <div className="flex flex-col items-center justify-center rounded-3xl border border-dashed border-gray-200 bg-gray-50/50 p-10 text-center">
      <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-white text-gray-400 shadow-sm">
        <Icon size={32} />
      </div>
      <h3 className="mb-2 text-lg font-bold text-gray-900">{title}</h3>
      <p className="mb-6 max-w-xs text-sm text-gray-500">{description}</p>
      {actionLabel && actionLink && (
        <Link
          to={actionLink}
          className="rounded-xl bg-primary-600 px-6 py-3 text-sm font-bold text-white shadow-lg shadow-primary-600/20 transition-all hover:bg-primary-700 active:scale-95"
        >
          {actionLabel}
        </Link>
      )}
    </div>
  );
};
