defmodule Mix.Tasks.Community.Install do
  use Igniter.Mix.Task
  alias Bonfire.Common.Mix.Tasks.Helpers

  @shortdoc "Install an extension into the parent app"
  @doc """
  Usage:
  `just mix social.install`
  """

  @app :community

  def igniter(igniter) do
    app_dir = Application.app_dir(@app)

    igniter
    # first we install Ember since this flavour includes that one
    |> Igniter.compose_task(Mix.Tasks.Social.Install, [])
    # then we run custom tasks for this flavour
    |> Helpers.igniter_copy(Path.join(app_dir, "priv/templates/lib/"), "lib/")
    |> Helpers.igniter_copy(
      Path.wildcard(Path.join(app_dir, "deps.*")),
      "config/current_flavour/"
    )
    # finally we run the standard installer for this flavour (which includes copying config and migrations)
    |> Igniter.compose_task(Mix.Tasks.Bonfire.Extension.Installer, [@app])
  end
end
