# Este fork não aplica o modelo de licenciamento comercial do Chatwoot — toda conta tem acesso
# total ao que seria "premium" (ver config/features.yml e migrations como
# LockInstallationPricingPlanEnterprise / EnableAdvancedAssignmentGlobally).
#
# Este serviço historicamente desligava features premium (enterprise/config/premium_features.yml)
# e resetava configs de branding — INSTALLATION_NAME/LOGO/BRAND_NAME/etc.
# (enterprise/config/premium_installation_config.yml) — toda madrugada em produção, sempre que o
# plano reportado pelo hub da Chatwoot (INSTALLATION_PRICING_PLAN) fosse 'community', que era o
# valor default nunca alterado nesta instalação. Isso desfazia customizações reais (ex. o rebrand
# da Noble) e qualquer feature destravada globalmente, de forma silenciosa.
#
# Neutralizado de propósito — ver claude/premium_unlock_tasks/00-visao-geral.md para o plano
# completo (3 camadas de defesa). Não reativar sem uma decisão de produto explícita de
# reintroduzir licenciamento real.
class Internal::ReconcilePlanConfigService
  def perform
    # no-op by design
  end
end
