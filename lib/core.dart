library;

export 'package:stickerdocs_core/src/main.dart'
    show initCore, CoreConfig, logic;

export 'package:stickerdocs_core/src/app_logic.dart'
    show AppLogicResult, AppLogic, FileSource, SearchContext;

export 'package:stickerdocs_core/src/app_state.dart'
    show AppState, SubscriptionStatus;

export 'package:stickerdocs_core/src/utils.dart'
    show
        formatInvitationToken,
        base64ToUint8List,
        platformName,
        isoDateToStringNow,
        newUuid,
        stringToUint8List,
        logger;

export 'package:stickerdocs_core/src/validation.dart' show isSDIDValid;

export 'package:stickerdocs_core/src/svg_security.dart' show isSafeSVG;
