#include "CurrencyManager/CurrencyManager.h"
#include "Hooks/Hooks.h"
#include "Papyrus/Papyrus.h"
#include "Serialization/Serde.h"
#include "Settings/INI/INISettings.h"

#ifdef SKYRIM_AE
extern "C" DLLEXPORT constinit auto SKSEPlugin_Version = []()
	{
		SKSE::PluginVersionData v{};

		v.PluginVersion(Plugin::VERSION);
		v.PluginName(Plugin::NAME);
		v.AuthorName("SeaSparrow"sv);
		v.UsesAddressLibrary();
		v.UsesUpdatedStructs();
		v.CompatibleVersions({ SKSE::RUNTIME_SSE_1_7_104 });

		return v;
	}();
#endif

#ifndef NDEBUG
void SetupLog() {
	auto logsFolder = SKSE::log::log_directory();
	if (!logsFolder) SKSE::stl::report_and_fail("SKSE log_directory not provided, logs disabled.");

	auto pluginName = Plugin::NAME;
	auto logFilePath = *logsFolder / std::format("{}.log", pluginName);
	auto fileLoggerPtr = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logFilePath.string(), true);
	auto loggerPtr = std::make_shared<spdlog::logger>("log", std::move(fileLoggerPtr));

	spdlog::set_default_logger(std::move(loggerPtr));
	spdlog::set_level(spdlog::level::debug);
	spdlog::flush_on(spdlog::level::debug);

	//Pattern
	spdlog::set_pattern("%v");
}
#endif

extern "C" DLLEXPORT bool SKSEAPI SKSEPlugin_Query(const SKSE::QueryInterface* a_skse, SKSE::PluginInfo* a_info)
{
	a_info->infoVersion = SKSE::PluginInfo::kVersion;
	a_info->name = Plugin::NAME.data();
	a_info->version = Plugin::VERSION[0];

	if (a_skse->IsEditor()) {
		logger::critical("Loaded in editor, marking as incompatible"sv);
		return false;
	}

	const auto ver = a_skse->RuntimeVersion();
#ifdef SKYRIM_AE
	if (ver != SKSE::RUNTIME_SSE_1_7_104) {
#else
	if (ver < SKSE::RUNTIME_1_5_39) {
#endif
		logger::critical(FMT_STRING("Unsupported runtime version {}"), ver.string());
		return false;
	}

	return true;
}

extern "C" DLLEXPORT bool SKSEAPI SKSEPlugin_Load(const SKSE::LoadInterface * a_skse)
{
#ifndef NDEBUG
	SetupLog();
	SKSE::Init(a_skse, false);
#else
	SKSE::Init(a_skse);
#endif
	SECTION_SEPARATOR;
	logger::info("{} v{}"sv, Plugin::NAME, Plugin::VERSION.string());
	logger::info("Author: SeaSparrow"sv);
	SECTION_SEPARATOR;

#ifdef SKYRIM_AE
	const auto ver = a_skse->RuntimeVersion();
	if (ver != SKSE::RUNTIME_SSE_1_7_104) {
		logger::critical(FMT_STRING("Unsupported runtime version {}; this build requires 1.7.104.0"), ver.string());
		return false;
	}
#endif

	logger::info("Performing startup tasks..."sv);

	if (!Settings::INI::Read()) {
		logger::critical("Failed to load INI settings. Currency Swapper will not be loaded."sv);
		return false;
	}
	if (!Hooks::Install()) {
		// One or more hooks may already point into this DLL. Failing the load and
		// allowing it to unload would leave dangling trampoline targets, so fail
		// closed through CommonLib's log-only, non-modal fatal path.
		SKSE::stl::report_and_fail("Failed to install hooks. Check the log for more information."sv);
	}
	if (!CurrencyManager::Initialize()) {
		SKSE::stl::report_and_fail("Failed to initialize Currency Manager after hooks were installed. Check the log for details."sv);
	}
	SKSE::GetPapyrusInterface()->Register(Papyrus::RegisterFunctions);

	SECTION_SEPARATOR;
	logger::info("Setting up serialization system..."sv);
	const auto serialization = SKSE::GetSerializationInterface();
	serialization->SetUniqueID(Serialization::ID);
	serialization->SetSaveCallback(&Serialization::SaveCallback);
	serialization->SetLoadCallback(&Serialization::LoadCallback);
	serialization->SetRevertCallback(&Serialization::RevertCallback);
	logger::info("  >Registered necessary functions."sv);
	SECTION_SEPARATOR;

	return true;
}
