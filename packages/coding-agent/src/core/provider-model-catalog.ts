import { type Api, type Model, parseModelCatalog } from "@earendil-works/pi-ai";

export const PROVIDER_MODEL_CATALOG_URL =
	"https://raw.githubusercontent.com/PrimeIntellect-ai/prime-agent-catalog/main/models/catalog.v1.json";

/**
 * Models the upstream catalog does not admit yet. Each fills a gap only in a provider the
 * catalog already serves, and a catalog entry with the same id always wins.
 */
const CATALOG_SUPPLEMENT_MODELS: readonly Model<Api>[] = [
	{
		id: "glm-5.4",
		name: "GLM-5.4",
		api: "openai-completions",
		provider: "zai",
		baseUrl: "https://api.z.ai/api/coding/paas/v4",
		compat: { supportsDeveloperRole: false, thinkingFormat: "zai", zaiToolStream: true },
		reasoning: true,
		thinkingLevelMap: { off: null, minimal: null, low: "low", medium: null, high: "high", xhigh: null, max: "max" },
		input: ["text", "image"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 1000000,
		maxTokens: 131072,
	} satisfies Model<"openai-completions">,
];

function withCatalogSupplements(models: readonly Model<Api>[]): Model<Api>[] {
	const ids = new Set(models.map((model) => JSON.stringify([model.provider, model.id])));
	const providers = new Set(models.map((model) => model.provider));
	return [
		...models,
		...CATALOG_SUPPLEMENT_MODELS.filter(
			(model) => providers.has(model.provider) && !ids.has(JSON.stringify([model.provider, model.id])),
		),
	];
}

/** Catalog data can select installed transports, but cannot change where credentials are sent. */
export function parseProviderModelCatalog(payload: unknown, bundledModels: readonly Model<Api>[]): Model<Api>[] {
	const transports = new Map(
		bundledModels.map((model) => [JSON.stringify([model.provider, model.api, model.baseUrl]), model]),
	);
	const exact = new Map(bundledModels.map((model) => [JSON.stringify([model.provider, model.id]), model]));
	const catalog = parseModelCatalog(payload, { skipInvalidModels: true });
	const models: Model<Api>[] = [];
	for (const model of withCatalogSupplements(catalog.models)) {
		if (model.provider === "prime-inference") continue;
		const transport = transports.get(JSON.stringify([model.provider, model.api, model.baseUrl]));
		if (!transport) continue;
		const template = exact.get(JSON.stringify([model.provider, model.id]));
		models.push({
			...model,
			api: transport.api,
			baseUrl: transport.baseUrl,
			headers: template?.headers ?? transport.headers,
		});
	}
	if (models.length === 0) throw new Error("Catalog has no models supported by this client");
	return models;
}
