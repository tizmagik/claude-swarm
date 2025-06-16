import { useState, useEffect } from 'react';
import { Link } from 'react-router';

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
    <div className="w-80 bg-gray-100 border-r border-gray-300 p-4 flex flex-col h-full">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-lg font-semibold">Swarms</h2>
        <button
          onClick={handleNewSwarm}
          className="px-3 py-1 bg-green-500 text-white rounded hover:bg-green-600 text-sm"
        >
          New
        </button>
      </div>
      
      <div className="flex-1 overflow-y-auto">
        {swarms.length === 0 ? (
          <div className="text-gray-500 text-center py-8">
            No swarms found. Create a new one to get started.
          </div>
        ) : (
          <div className="space-y-2">
            {swarms.map((swarm) => (
              <div
                key={swarm.filename}
                onClick={() => onSwarmSelect(swarm)}
                className={`p-3 rounded cursor-pointer transition-colors ${
                  selectedSwarm?.filename === swarm.filename
                    ? 'bg-blue-100 border-blue-300 border'
                    : 'bg-white hover:bg-gray-50 border border-gray-200'
                }`}
              >
                <div className="font-medium text-sm">{swarm.name}</div>
                <div className="text-xs text-gray-500 mt-1">{swarm.filename}</div>
                <div className="text-xs text-gray-400 mt-1">
                  Main: {swarm.main} | {swarm.instances.length} instances
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-gray-300">
        <Link
          to="/agent-templates"
          className="block w-full px-3 py-2 text-sm bg-blue-500 text-white rounded hover:bg-blue-600 text-center"
        >
          Manage Agent Templates
        </Link>
        <Link
          to="/mcp-tools"
          className="block w-full px-3 py-2 mt-2 text-sm bg-purple-500 text-white rounded hover:bg-purple-600 text-center"
        >
          Manage MCP Tools
        </Link>
      </div>
    </div>
  );
}