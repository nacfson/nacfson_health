.PHONY: install-ios run-ios-dev build-ipa build-ios clean

# 환경 변수는 `--dart-define-from-file=.env` 로 빌드 시점에 주입.
# `.env` 는 .gitignore 에 등록되어 있고, asset 으로는 번들되지 않는다.
DEFINES = --dart-define-from-file=.env

install-ios:
	flutter run --release -d iphone $(DEFINES)

run-ios-dev:
	flutter run --debug -d iphone $(DEFINES)

build-ipa:
	flutter build ipa --release $(DEFINES)

build-ios:
	flutter build ios --release --no-codesign $(DEFINES)

clean:
	flutter clean && cd ios && pod install
