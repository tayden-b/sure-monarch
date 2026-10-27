class Settings::McpController < ApplicationController
  include OauthBase
  layout "settings"

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.mcp"), nil ]
    ]
    @mcp_url = "#{configured_base_url}/mcp"
    @env_tokens = configured_env_tokens
    @env_token_user_email = ENV["MCP_USER_EMAIL"].presence
    @connected_tokens = Doorkeeper::AccessToken
      .where(resource_owner_id: Current.user.id, revoked_at: nil, mobile_device_id: nil)
      .includes(:application)
      .order(created_at: :desc)
      .to_a
  end

  def revoke
    token = Doorkeeper::AccessToken.find_by( # pipelock:ignore
      id: params[:token_id],
      resource_owner_id: Current.user.id
    )
    token&.revoke
    redirect_to settings_mcp_path, notice: t(".revoked")
  end

  private

    # Static bearer tokens configured on this deployment, shown masked so an
    # operator can tell which clients can only read and which can write. The
    # full values live only in the deployment's .env.
    def configured_env_tokens
      [
        { env_var: "MCP_API_TOKEN", scope: :read_write },
        { env_var: "MCP_API_TOKEN_READONLY", scope: :read }
      ].filter_map do |entry|
        token = ENV[entry[:env_var]].presence
        next unless token

        entry.merge(masked_token: mask_env_token(token))
      end
    end

    # Named mask_env_token, not mask_token: ActionController's forgery
    # protection defines its own private mask_token (used by csrf_meta_tags
    # via masked_authenticity_token), and shadowing it makes every render
    # raise Encoding::CompatibilityError on the binary CSRF secret.
    def mask_env_token(token)
      return "••••" if token.length < 12

      "#{token.first(4)}••••#{token.last(4)}"
    end
end
