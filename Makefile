.PHONY: install-ios run-ios-dev build-ipa build-ios clean

install-ios:
	flutter run --release -d iphone

run-ios-dev:
	flutter run --debug -d iphone

build-ipa:
	flutter build ipa --release

build-ios:
	flutter build ios --release --no-codesign

clean:
	flutter clean && cd ios && pod install
