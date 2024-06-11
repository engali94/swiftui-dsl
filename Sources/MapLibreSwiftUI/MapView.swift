import InternalUtils
import MapLibre
import MapLibreSwiftDSL
import SwiftUI

public struct MapView<T: WrappedViewController>: UIViewControllerRepresentable {
    public typealias UIViewControllerType = T
    var cameraDisabled: Bool = true

    @Binding var camera: MapViewCamera

    let makeViewController: (() -> T)?
    let styleSource: MapStyleSource
    let userLayers: [StyleLayerDefinition]

    var gestures = [MapGesture]()

    var onStyleLoaded: ((MLNStyle) -> Void)?
    var onViewPortChanged: ((MapViewPort) -> Void)?

    public var mapViewContentInset: UIEdgeInsets = .zero

    /// 'Escape hatch' to MLNMapView until we have more modifiers.
    /// See ``unsafeMapViewModifier(_:)``
    var unsafeMapViewModifier: ((T.MapType) -> Void)?

    var unsafeMapViewControllerModifier: ((T) -> Void)?

    var controls: [MapControl] = [
        CompassView(),
        LogoView(),
        AttributionButton(),
    ]

    private var locationManager: MLNLocationManager?

    var clusteredLayers: [ClusterLayer]?

    public init(
        makeViewController: @autoclosure @escaping () -> T,
        styleURL: URL,
        camera: Binding<MapViewCamera> = .constant(.default()),
        locationManager: MLNLocationManager? = nil,
        @MapViewContentBuilder _ makeMapContent: () -> [StyleLayerDefinition] = { [] }
    ) {
        self.makeViewController = makeViewController
        styleSource = .url(styleURL)
        _camera = camera
        userLayers = makeMapContent()
        self.locationManager = locationManager
    }

    public init(
        styleURL: URL,
        camera: Binding<MapViewCamera> = .constant(.default()),
        locationManager: MLNLocationManager? = nil,
        @MapViewContentBuilder _ makeMapContent: () -> [StyleLayerDefinition] = { [] }
    ) {
        makeViewController = nil
        styleSource = .url(styleURL)
        _camera = camera
        userLayers = makeMapContent()
        self.locationManager = locationManager
    }

    public func makeCoordinator() -> MapViewCoordinator<T> {
        MapViewCoordinator<T>(
            parent: self,
            onGesture: { processGesture($0, $1) },
            onViewPortChanged: { onViewPortChanged?($0) }
        )
    }

    public func makeUIViewController(context: Context) -> T {
        // Create the map view
        let controller = makeViewController?() ?? T()
        controller.mapView.delegate = context.coordinator
        context.coordinator.mapView = controller.mapView

        // Apply modifiers, suppressing camera update propagation (this messes with setting our initial camera as
        // content insets can trigger a change)
        context.coordinator.suppressCameraUpdatePropagation = true
        applyModifiers(controller, runUnsafe: false)
        context.coordinator.suppressCameraUpdatePropagation = false

        controller.mapView.locationManager = locationManager

        switch styleSource {
        case let .url(styleURL):
            controller.mapView.styleURL = styleURL
        }

        context.coordinator.updateCamera(mapView: controller.mapView,
                                         camera: $camera.wrappedValue,
                                         animated: false)
        controller.mapView.locationManager = controller.mapView.locationManager

        // Link the style loaded to the coordinator that emits the delegate event.
        context.coordinator.onStyleLoaded = onStyleLoaded

        // Add all gesture recognizers
        for gesture in gestures {
            registerGesture(controller.mapView, context, gesture: gesture)
        }

        return controller
    }

    public func updateUIViewController(_ uiViewController: T, context: Context) {
        context.coordinator.parent = self

        applyModifiers(uiViewController, runUnsafe: true)

        // FIXME: This should be a more selective update
        context.coordinator.updateStyleSource(styleSource, mapView: uiViewController.mapView)
        context.coordinator.updateLayers(mapView: uiViewController.mapView)

        // FIXME: This isn't exactly telling us if the *map* is loaded, and the docs for setCenter say it needs to be.
        let isStyleLoaded = uiViewController.mapView.style != nil

        if cameraDisabled == false {
            context.coordinator.updateCamera(mapView: uiViewController.mapView,
                                             camera: $camera.wrappedValue,
                                             animated: isStyleLoaded)
        }
    }

    @MainActor private func applyModifiers(_ mapViewController: T, runUnsafe: Bool) {
        mapViewController.mapView.contentInset = mapViewContentInset

        // Assume all controls are hidden by default (so that an empty list returns a map with no controls)
        mapViewController.mapView.logoView.isHidden = true
        mapViewController.mapView.compassView.isHidden = true
        mapViewController.mapView.attributionButton.isHidden = true

        // Apply each control configuration
        for control in controls {
            control.configureMapView(mapViewController.mapView)
        }

        if runUnsafe {
            unsafeMapViewControllerModifier?(mapViewController)
        }
    }
}

#Preview {
    MapView<MapViewController>(styleURL: demoTilesURL)
        .ignoresSafeArea(.all)
        .previewDisplayName("Vanilla Map")

    // For a larger selection of previews,
    // check out the Examples directory, which
    // has a wide variety of previews,
    // organized into (hopefully) useful groups
}
