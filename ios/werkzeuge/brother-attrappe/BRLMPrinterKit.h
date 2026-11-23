// ATTRAPPE — NICHT das Brother Print SDK.
// Nur die Schnittstellen, die KAIBSB/Drucker.swift benutzt (Namen und Signaturen wie im Brother Print SDK v4 für iOS),
// damit GitHub den Druckcode ohne das lizenzierte SDK auf Tippfehler prüfen kann:
//   swiftc -typecheck -I werkzeuge/brother-attrappe KAIBSB/*.swift
// Beim echten Bauen wird diese Datei nicht benutzt.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString BRLMExternalAccessorySerialNumber;
typedef NSString BRLMChannelExtraInfoKey;
extern BRLMChannelExtraInfoKey * _Nonnull const BRLMChannelExtraInfoKeyModelName;

typedef NS_ENUM(NSInteger, BRLMChannelType) {
    BRLMChannelTypeBluetoothMFi,
    BRLMChannelTypeWiFi,
    BRLMChannelTypeBluetoothLowEnergy,
};

typedef NS_ENUM(NSInteger, BRLMPrinterModel) {
    BRLMPrinterModelPJ_673,
    BRLMPrinterModelPT_P750W,
    BRLMPrinterModelPT_P710BT,
    BRLMPrinterModelPT_P910BT,
};

@interface BRLMChannel : NSObject
@property (nonatomic, readonly) BRLMChannelType channelType;
@property (nonatomic, readonly) NSString *channelInfo;
@property (nonatomic, readonly, nullable) NSMutableDictionary<BRLMChannelExtraInfoKey*, NSString*> *extraInfo;
- (instancetype)initWithWifiIPAddress:(NSString *)ipAddress;
- (instancetype)initWithBluetoothSerialNumber:(BRLMExternalAccessorySerialNumber *)serialNumber;
- (instancetype)init __unavailable;
@end

typedef NS_ENUM(NSInteger, BRLMOpenChannelErrorCode) {
    BRLMOpenChannelErrorCodeNoError = 30000,
    BRLMOpenChannelErrorCodeOpenStreamFailure,
    BRLMOpenChannelErrorCodeTimeout,
};

@interface BRLMOpenChannelError : NSObject
@property (nonatomic, readonly) BRLMOpenChannelErrorCode code;
@end

typedef NS_ENUM(NSInteger, BRLMPrintErrorCode) {
    BRLMPrintErrorCodeNoError = 0,
    BRLMPrintErrorCodePrintSettingsError,
    BRLMPrintErrorCodeFilepathURLError,
    BRLMPrintErrorCodePDFPageError,
    BRLMPrintErrorCodePrintSettingsNotSupportError,
    BRLMPrintErrorCodeDataBufferError,
    BRLMPrintErrorCodePrinterModelError,
    BRLMPrintErrorCodeCanceled,
    BRLMPrintErrorCodeChannelTimeout,
    BRLMPrintErrorCodeSetModelError,
    BRLMPrintErrorCodeUnsupportedFile,
    BRLMPrintErrorCodeSetMarginError,
    BRLMPrintErrorCodeSetLabelSizeError,
    BRLMPrintErrorCodeCustomPaperSizeError,
    BRLMPrintErrorCodeSetLengthError,
    BRLMPrintErrorCodeTubeSettingError,
    BRLMPrintErrorCodeChannelErrorStreamStatusError,
    BRLMPrintErrorCodeChannelErrorUnsupportedChannel,
    BRLMPrintErrorCodePrinterStatusErrorPaperEmpty,
    BRLMPrintErrorCodePrinterStatusErrorCoverOpen,
    BRLMPrintErrorCodePrinterStatusErrorBusy,
    BRLMPrintErrorCodePrinterStatusErrorPrinterTurnedOff,
    BRLMPrintErrorCodePrinterStatusErrorBatteryWeak,
    BRLMPrintErrorCodeUnknownError,
};

@interface BRLMPrintError : NSObject
@property (nonatomic, readonly) BRLMPrintErrorCode code;
@property (nonatomic, readonly) NSString *errorDescription;
@end

@protocol BRLMPrintSettingsProtocol <NSObject>
@end

typedef NS_ENUM(NSInteger, BRLMPTPrintSettingsLabelSize) {
    BRLMPTPrintSettingsLabelSizeWidth3_5mm,
    BRLMPTPrintSettingsLabelSizeWidth6mm,
    BRLMPTPrintSettingsLabelSizeWidth9mm,
    BRLMPTPrintSettingsLabelSizeWidth12mm,
    BRLMPTPrintSettingsLabelSizeWidth18mm,
    BRLMPTPrintSettingsLabelSizeWidth24mm,
    BRLMPTPrintSettingsLabelSizeWidth36mm,
};

@interface BRLMPTPrintSettings : NSObject <BRLMPrintSettingsProtocol>
@property (nonatomic) BRLMPTPrintSettingsLabelSize labelSize;
@property (nonatomic) BOOL autoCut;
- (nullable instancetype)initDefaultPrintSettingsWithPrinterModel:(BRLMPrinterModel)model;
@end

@interface BRLMPrinterDriver : NSObject
- (BRLMPrintError *)printImageWithURL:(NSURL *)url settings:(id<BRLMPrintSettingsProtocol>)settings;
- (BRLMPrintError *)printImageWithImage:(CGImageRef)imageRef settings:(id<BRLMPrintSettingsProtocol>)settings;
- (void)closeChannel;
@end

@interface BRLMPrinterDriverGenerateResult : NSObject
@property (nonatomic, readonly) BRLMOpenChannelError *error;
@property (nonatomic, readonly, nullable) BRLMPrinterDriver *driver;
@end

@interface BRLMPrinterDriverGenerator : NSObject
+ (BRLMPrinterDriverGenerateResult *)openChannel:(BRLMChannel *)channel;
@end

@interface BRLMNetworkSearchOption : NSObject
@property (nonatomic, nullable) NSArray<NSString *> *printerList;
@property (nonatomic) NSTimeInterval searchDuration;
@end

@interface BRLMPrinterSearchResult : NSObject
@property (nonatomic, readonly) NSArray<BRLMChannel *> *channels;
@end

@interface BRLMPrinterSearcher : NSObject
+ (BRLMPrinterSearchResult *)startNetworkSearch:(nullable BRLMNetworkSearchOption *)searchOption callback:(nullable void (^)(BRLMChannel *channel))callback;
@end

NS_ASSUME_NONNULL_END
