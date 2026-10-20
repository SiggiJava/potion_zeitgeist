defmodule PotionZeitgeistWeb.ProjectComponents do
  @moduledoc """
  Components for booking time entries to projects.
  """
  use Phoenix.Component

  @doc """
  Renders a project select with a "No project" option first.

  Archived projects in the list (an entry's current project) are marked as such.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :projects, :list, required: true
  attr :selected, :any, default: nil
  attr :class, :string, default: "select select-bordered w-full"
  attr :rest, :global

  def project_select(assigns) do
    ~H"""
    <select id={@id} name={@name} class={@class} {@rest}>
      <option value="" selected={is_nil(@selected)}>No project</option>
      <option
        :for={project <- @projects}
        value={project.id}
        selected={project.id == @selected}
      >
        {project.name}{if !project.active, do: " (archived)"}
      </option>
    </select>
    """
  end
end
