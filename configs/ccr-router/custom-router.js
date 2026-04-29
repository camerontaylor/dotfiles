"use strict";

module.exports = async function router(req, config) {
  const requestedModel = req?.body?.model;
  if (typeof requestedModel !== "string" || requestedModel.length === 0) {
    return null;
  }

  if (requestedModel.includes(",")) {
    return null;
  }

  const providers = Array.isArray(config?.Providers) ? config.Providers : [];
  const liteLlmFleet = providers.find((provider) => provider?.name === "litellm-fleet");
  const models = Array.isArray(liteLlmFleet?.models) ? liteLlmFleet.models : [];

  if (!models.includes(requestedModel)) {
    return null;
  }

  return `litellm-fleet,${requestedModel}`;
};
