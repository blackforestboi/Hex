import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct IndicatorSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			Label {
				Picker("Size", selection: $store.hexSettings.indicatorSize) {
					ForEach(IndicatorSize.allCases, id: \.self) { size in
						Text(size.displayName).tag(size)
					}
				}
				.pickerStyle(.menu)
			} icon: {
				Image(systemName: "rectangle.expand.vertical")
			}

			Label {
				Picker("Location", selection: $store.hexSettings.indicatorLocation) {
					ForEach(IndicatorLocation.allCases, id: \.self) { location in
						Text(location.displayName).tag(location)
					}
				}
				.pickerStyle(.menu)
			} icon: {
				Image(systemName: "rectangle.inset.filled.and.cursorarrow")
			}
		} header: {
			Text("Transcription Indicator")
		} footer: {
			Text("Click the indicator while it is visible to open History.")
		}
		.enableInjection()
	}
}
