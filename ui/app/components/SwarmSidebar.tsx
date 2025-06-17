import { useState, useEffect } from 'react';
import { Link } from 'react-router';
import { Zap, Plus, Users, Settings, Wrench } from 'lucide-react';

export interface SwarmSummary {
  filename: string;
  name: string;
  main: string;
  instances: string[];
}

interface SwarmSidebarProps {
  onSwarmSelect: (swarm: SwarmSummary) => void;
  selectedSwarm: SwarmSummary | null;
}

export default function SwarmSidebar({ onSwarmSelect, selectedSwarm }: SwarmSidebarProps) {
  const [swarms, setSwarms] = useState<SwarmSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchSwarms();
  }, []);

  const fetchSwarms = async () => {
    try {
      const response = await fetch('/api/swarms');
      if (!response.ok) throw new Error('Failed to fetch swarms');
      const data = await response.json();
      setSwarms(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const handleNewSwarm = () => {
    const filename = prompt('Enter filename for new swarm (e.g., my-swarm.yml):');
    if (filename && !filename.endsWith('.yml')) {
      alert('Filename must end with .yml');
      return;
    }
    if (filename) {
      const newSwarm: SwarmSummary = {
        filename,
        name: 'New Swarm',
        main: 'main_instance',
        instances: ['main_instance']
      };
      onSwarmSelect(newSwarm);
    }
  };

  if (loading) {
    return (
      <div className="w-80 bg-gray-100 border-r border-gray-300 p-4">
        <div className="animate-pulse">Loading swarms...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="w-80 bg-gray-100 border-r border-gray-300 p-4">
        <div className="text-red-600">Error: {error}</div>
        <button 
          onClick={fetchSwarms}
          className="mt-2 px-3 py-1 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="w-80 lg:w-80 md:w-72 sm:w-64 bg-slate-900 border-r border-slate-700 flex flex-col h-full">
      <div className="p-4 lg:p-6 border-b border-slate-700 flex-shrink-0">
        <div className="flex justify-between items-center">
          <h2 className="text-lg lg:text-xl font-bold text-white flex items-center">
            <Zap className="w-5 h-5 mr-2 text-blue-400" />
            <span className="hidden sm:inline">Swarms</span>
          </h2>
          <button
            onClick={handleNewSwarm}
            className="px-3 py-2 text-sm text-slate-400 hover:text-slate-200 border border-slate-600 hover:border-slate-500 rounded-lg hover:bg-slate-700/50 transition-colors flex items-center"
          >
            <Plus className="w-4 h-4 mr-1" />
            <span className="hidden sm:inline">New</span>
          </button>
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto p-3 lg:p-4 min-h-0">
        {swarms.length === 0 ? (
          <div className="text-slate-300 text-center py-8 lg:py-12">
            <Zap className="w-12 h-12 mx-auto text-slate-400 mb-4" />
            <div className="text-base lg:text-lg font-medium mb-2 text-white">No swarms found</div>
            <div className="text-sm text-slate-400">Create a new one to get started</div>
          </div>
        ) : (
          <div className="space-y-2 lg:space-y-3">
            {swarms.map((swarm) => (
              <div
                key={swarm.filename}
                onClick={() => onSwarmSelect(swarm)}
                className={`p-3 lg:p-4 rounded-xl cursor-pointer transition-all duration-200 ${
                  selectedSwarm?.filename === swarm.filename
                    ? 'bg-blue-600 shadow-lg shadow-blue-500/25 border border-blue-400'
                    : 'bg-slate-800 hover:bg-slate-750 border border-slate-700 hover:border-slate-600 hover:shadow-lg'
                }`}
              >
                <div className={`font-semibold text-sm lg:text-base mb-2 ${
                  selectedSwarm?.filename === swarm.filename ? 'text-white' : 'text-white'
                }`}>{swarm.name}</div>
                <div className={`text-xs lg:text-sm mb-2 font-mono truncate ${
                  selectedSwarm?.filename === swarm.filename ? 'text-blue-100' : 'text-slate-400'
                }`}>{swarm.filename}</div>
                <div className="flex items-center justify-between text-xs">
                  <div className={`truncate mr-2 ${
                    selectedSwarm?.filename === swarm.filename ? 'text-blue-200' : 'text-slate-500'
                  }`}>
                    <span className="font-medium">Main:</span> <span className="hidden sm:inline">{swarm.main}</span>
                  </div>
                  <div className={`px-2 py-1 rounded-full flex items-center ${
                    selectedSwarm?.filename === swarm.filename 
                      ? 'bg-blue-500 text-white' 
                      : 'bg-slate-700 text-slate-300'
                  }`}>
                    <Users className="w-3 h-3 mr-1" />
                    {swarm.instances.length}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

    </div>
  );
}