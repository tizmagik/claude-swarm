import { useCallback, useEffect } from "react";
import {
  Edit3,
  X,
  Save,
  Bot,
  Settings,
  Wrench,
  Folder,
  Trash2,
} from "lucide-react";
import type { AgentNode, AgentEditForm } from "../types/swarm";

interface AgentEditModalProps {
  editingNode: AgentNode | null;
  editForm: AgentEditForm;
  setEditForm: React.Dispatch<React.SetStateAction<AgentEditForm>>;
  onSave: () => void;
  onCancel: () => void;
  onDelete?: (nodeId: string) => void;
}

export default function AgentEditModal({
  editingNode,
  editForm,
  setEditForm,
  onSave,
  onCancel,
  onDelete,
}: AgentEditModalProps) {
  // Add keyboard event listener for Escape key to close modal
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && editingNode) {
        onCancel();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [editingNode, onCancel]);

  const handleToolAdd = useCallback(
    (tool: string) => {
      if (tool && !editForm.tools.includes(tool)) {
        setEditForm((prev) => ({
          ...prev,
          tools: [...prev.tools, tool],
        }));
      }
    },
    [editForm.tools, setEditForm]
  );

  const handleToolRemove = useCallback((tool: string) => {
    setEditForm((prev) => ({
      ...prev,
      tools: prev.tools.filter((t) => t !== tool),
    }));
  }, [setEditForm]);

  const handleMcpRemove = useCallback((mcp: string) => {
    setEditForm((prev) => ({
      ...prev,
      mcps: prev.mcps.filter((m) => m !== mcp),
    }));
  }, [setEditForm]);

  if (!editingNode) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-xl p-6 w-full max-w-2xl mx-4 max-h-[90vh] overflow-y-auto border border-slate-700">
        {/* Modal Header */}
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-bold text-white flex items-center">
            <Edit3 className="w-5 h-5 mr-2 text-blue-400" />
            Edit Agent: {editingNode.name}
          </h2>
          <button
            onClick={onCancel}
            className="text-slate-400 hover:text-white transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form Fields */}
        <div className="space-y-6">
          {/* Name */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              <Bot className="w-4 h-4 inline mr-1" />
              Agent Name
            </label>
            <input
              type="text"
              value={editForm.name}
              onChange={(e) =>
                setEditForm((prev) => ({ ...prev, name: e.target.value }))
              }
              className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              placeholder="Enter agent name"
            />
          </div>

          {/* Model */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              <Settings className="w-4 h-4 inline mr-1" />
              Model
            </label>
            <select
              value={editForm.model}
              onChange={(e) =>
                setEditForm((prev) => ({ ...prev, model: e.target.value }))
              }
              className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="sonnet">Claude 3.5 Sonnet</option>
              <option value="opus">Claude 3 Opus</option>
              <option value="haiku">Claude 3 Haiku</option>
            </select>
          </div>

          {/* Working Directories */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              <Folder className="w-4 h-4 inline mr-1" />
              Working Directories
            </label>
            <div className="flex flex-wrap gap-2 mb-2">
              {editForm.directories.map((dir, index) => (
                <span
                  key={index}
                  className="inline-flex items-center px-3 py-1 bg-green-600 text-white text-sm rounded-full"
                >
                  {dir}
                  <button
                    onClick={() => {
                      setEditForm((prev) => ({
                        ...prev,
                        directories: prev.directories.filter((_, i) => i !== index)
                      }));
                    }}
                    className="ml-2 text-green-200 hover:text-white"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              ))}
              {editForm.directories.length === 0 && (
                <span className="text-slate-400 text-sm">
                  No directories configured
                </span>
              )}
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                placeholder="Add directory (e.g., ., ./frontend, ~/projects)"
                className="flex-1 px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && e.currentTarget.value.trim()) {
                    const newDir = e.currentTarget.value.trim();
                    if (!editForm.directories.includes(newDir)) {
                      setEditForm((prev) => ({
                        ...prev,
                        directories: [...prev.directories, newDir]
                      }));
                    }
                    e.currentTarget.value = "";
                  }
                }}
              />
            </div>
            <div className="text-xs text-slate-400 mt-1">
              Press Enter to add. First directory is primary, additional are accessible via --add-dir. Use "." for current directory.
            </div>
          </div>

          {/* Description */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              Description
            </label>
            <textarea
              value={editForm.description}
              onChange={(e) =>
                setEditForm((prev) => ({
                  ...prev,
                  description: e.target.value,
                }))
              }
              className="w-full px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              placeholder="Describe what this agent does"
              rows={3}
            />
          </div>

          {/* Tools */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              <Wrench className="w-4 h-4 inline mr-1" />
              Tools
            </label>
            <div className="flex flex-wrap gap-2 mb-2">
              {editForm.tools.map((tool, index) => (
                <span
                  key={index}
                  className="inline-flex items-center px-3 py-1 bg-blue-600 text-white text-sm rounded-full"
                >
                  {tool}
                  <button
                    onClick={() => handleToolRemove(tool)}
                    className="ml-2 text-blue-200 hover:text-white"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                placeholder="Add a tool (e.g., Read, Edit, Bash)"
                className="flex-1 px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    handleToolAdd(e.currentTarget.value);
                    e.currentTarget.value = "";
                  }
                }}
              />
            </div>
            <div className="text-xs text-slate-400 mt-1">
              Press Enter to add. Common tools: Read, Edit, Write, Bash, Grep, Glob
            </div>
          </div>

          {/* Current MCPs Display */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">
              <Wrench className="w-4 h-4 inline mr-1" />
              MCP Integrations
            </label>
            <div className="flex flex-wrap gap-2 mb-2">
              {editForm.mcps.map((mcp, index) => (
                <span
                  key={index}
                  className="inline-flex items-center px-3 py-1 bg-purple-600 text-white text-sm rounded-full"
                >
                  {mcp}
                  <button
                    onClick={() => handleMcpRemove(mcp)}
                    className="ml-2 text-purple-200 hover:text-white transition-colors"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              ))}
              {editForm.mcps.length === 0 && (
                <span className="text-slate-400 text-sm">
                  No MCP integrations
                </span>
              )}
            </div>
            <div className="text-xs text-slate-400">
              Drag and drop MCP tools from the sidebar to add them, or click
              the × to remove them
            </div>
          </div>
        </div>

        {/* Modal Footer */}
        <div className="flex justify-between mt-8">
          <div>
            {onDelete && (
              <button
                onClick={() => {
                  if (
                    editingNode &&
                    confirm(
                      `Are you sure you want to delete agent "${editingNode.name}"?`
                    )
                  ) {
                    onDelete(editingNode.id);
                  }
                }}
                className="px-4 py-2 text-red-400 hover:text-red-300 border border-red-600 hover:border-red-500 rounded-lg hover:bg-red-600/10 transition-colors flex items-center"
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Delete Agent
              </button>
            )}
          </div>
          <div className="flex gap-3">
            <button
              onClick={onCancel}
              className="px-4 py-2 text-slate-400 hover:text-white border border-slate-600 rounded-lg hover:border-slate-500 transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={onSave}
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-500 transition-colors flex items-center"
            >
              <Save className="w-4 h-4 mr-2" />
              Save Changes
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}