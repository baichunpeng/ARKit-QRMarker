//
//  ViewController.swift
//  ARKit + QRMark
//
//  Created by Eugene Bokhan on 7/4/17.
//  Copyright © 2017 Eugene Bokhan. All rights reserved.
//

import ARKit
import UIKit
import Vision

class ViewController: UIViewController, ARSCNViewDelegate {
    
    private var requests = [VNRequest]()
    private lazy var drawLayer: CAShapeLayer = {
        let drawLayer = CAShapeLayer()
        self.view.layer.addSublayer(drawLayer)
        drawLayer.frame = self.view.bounds
        drawLayer.strokeColor = UIColor.green.cgColor
        drawLayer.lineWidth = 3
        drawLayer.lineJoin = kCALineJoinMiter
        drawLayer.fillColor = UIColor.clear.cgColor
        return drawLayer
    }()
    
    var pointGeom: SCNGeometry = {
        let geo = SCNSphere(radius: 0.002)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.blue
        material.locksAmbientWithDiffuse = true
        geo.firstMaterial = material
        return geo
    }()
    
    let earthGeometry: SCNGeometry = {
        let earth = SCNSphere(radius: 0.05)
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = UIImage(named: "earth_diffuse_4k")
        earthMaterial.specular.contents = UIImage(named: "earth_specular_1k")
        earthMaterial.emission.contents = UIImage(named: "earth_lights_4k")
        earthMaterial.normal.contents = UIImage(named: "earth_normal_4k")
        earthMaterial.multiply.contents = UIColor(white:  0.7, alpha: 1)
        earthMaterial.shininess = 0.05
        earth.firstMaterial = earthMaterial
        return earth
    }()
    
    var topLeftPointNode = SCNNode()
    var topRightPointNode = SCNNode()
    var bottomLeftPointNode = SCNNode()
    var bottomRightPointNode = SCNNode()
    var axesNode = createAxesNode(quiverLength: 0.1, quiverThickness: 1.0)
    var earthNode = SCNNode()
    var nodes = [SCNNode]()
    
    private let bufferQueue = DispatchQueue(label: "com.evgeniybokhan.BufferQueue",
                                            qos: .userInteractive,
                                            attributes: .concurrent)
    
    @IBAction func showButton(_ sender: UIButton) {
        addEarthNode()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupFocusSquare()
        setupVision()
        setupNodes()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start the ARSession.
        restartPlaneDetection()
    }
    
    // MARK: - ARKit / ARSCNView
    let session = ARSession()
    var sessionConfig: ARSessionConfiguration = ARWorldTrackingSessionConfiguration()
    @IBOutlet var sceneView: ARSCNView!
    var screenCenter: CGPoint?
    
    func setupScene() {
        // set up sceneView
        sceneView.delegate = self
        sceneView.session = session
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = false
        
        sceneView.preferredFramesPerSecond = 60
        sceneView.contentScaleFactor = 1.3
        //sceneView.showsStatistics = true
        
        //enableEnvironmentMapWithIntensity(25.0)
        
        DispatchQueue.main.async {
            self.screenCenter = self.sceneView.bounds.mid
        }
        
        if let camera = sceneView.pointOfView?.camera {
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = true
            camera.exposureOffset = -1
            camera.minimumExposure = -1
        }
    }
    
    func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
    func restartPlaneDetection() {
        
        // configure session
        if let worldSessionConfig = sessionConfig as? ARWorldTrackingSessionConfiguration {
            worldSessionConfig.planeDetection = .horizontal
            session.run(worldSessionConfig, options: [.resetTracking, .removeExistingAnchors])
        }
        
        // reset timer
        //        if trackingFallbackTimer != nil {
        //            trackingFallbackTimer!.invalidate()
        //            trackingFallbackTimer = nil
        //        }
        //
        //        textManager.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT",
        //                                    inSeconds: 7.5,
        //                                    messageType: .planeEstimation)
    }
    
    // MARK: - SCNNodes
    
    func setupNodes() {
        topLeftPointNode.name = "Top Left"
        topLeftPointNode.geometry = self.pointGeom
        nodes.append(topLeftPointNode)
        topRightPointNode.name = "Top Right"
        topRightPointNode.geometry = self.pointGeom
        nodes.append(topRightPointNode)
        bottomLeftPointNode.name = "Bottom Left"
        bottomLeftPointNode.geometry = self.pointGeom
        nodes.append(bottomLeftPointNode)
        
        // create and add a light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = SCNLight.LightType.omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        sceneView.scene.rootNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = SCNLight.LightType.ambient
        ambientLightNode.light!.color = UIColor.darkGray
        sceneView.scene.rootNode.addChildNode(ambientLightNode)
        
        // The Earth
        earthNode.geometry = earthGeometry
        
        let rotate = CABasicAnimation(keyPath:"rotation.w") // animate the angle
        rotate.byValue   = Double.pi * 20.0
        rotate.duration  = 100.0;
        rotate.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        rotate.repeatCount = Float.infinity;
        
        earthNode.position.x = 0.08
        earthNode.position.y = 0.08
        earthNode.position.z = -0.08
        earthNode.rotation = SCNVector4Make(1, 0, 0, Float(Double.pi/6));
        earthNode.addAnimation(rotate, forKey: "rotate the earth")
        
        // Create a larger sphere to look like clouds
        let clouds = SCNSphere(radius: 0.053)
        clouds.segmentCount = 144; // 3 times the default
        let cloudsMaterial = SCNMaterial()
        
        cloudsMaterial.diffuse.contents = UIColor.white
        cloudsMaterial.locksAmbientWithDiffuse = true
        // Use a texture where RGB (or lack thereof) determines transparency of the material
        cloudsMaterial.transparent.contents = UIImage(named: "clouds_transparent_2K")
        cloudsMaterial.transparencyMode = SCNTransparencyMode.rgbZero;
        
        // Don't have the clouds cast shadows
        cloudsMaterial.writesToDepthBuffer = false;
        
        clouds.firstMaterial = cloudsMaterial;
        let cloudNode = SCNNode(geometry: clouds)
        
        earthNode.addChildNode(cloudNode)
        
        earthNode.rotation = SCNVector4Make(0, 1, 0, 0); // specify the rotation axis
        cloudNode.rotation = SCNVector4Make(0, 1, 0, 0); // specify the rotation axis
        
        // Animate the rotation of the earth and the clouds
        // ------------------------------------------------
        let rotateClouds = CABasicAnimation(keyPath: "rotation.w") // animate the angle
        rotateClouds.byValue   = -Double.pi * 2.0
        rotateClouds.duration  = 150.0;
        rotateClouds.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        rotateClouds.repeatCount = Float.infinity;
        cloudNode.addAnimation(rotateClouds, forKey:"slowly move the clouds")
    }
    
    // MARK: - Vision
    
    func setupVision() {
        let barcodeRequest = VNDetectBarcodesRequest(completionHandler: barcodeDetectionHandler)
        barcodeRequest.symbologies = [.QR] // VNDetectBarcodesRequest.supportedSymbologies
        self.requests = [barcodeRequest]
    }
    
    func barcodeDetectionHandler(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }
        
        DispatchQueue.main.async() {
            // Loop through the results found.
            let path = CGMutablePath()
            
            guard let frame = self.sceneView.session.currentFrame else {
                return
            }
            
            guard let featurePointCloud = frame.rawFeaturePoints else {
                return
            }
            
            for result in results {
                guard let barcode = result as? VNBarcodeObservation else { continue }
                let topLeft = (name: "Top Left", position: self.convert(point: barcode.topLeft))
                path.move(to: topLeft.position)
                let topRight = (name: "Top Right", position: self.convert(point: barcode.topRight))
                path.addLine(to: topRight.position)
                let bottomRight = (name: "Bottom Right", position: self.convert(point: barcode.bottomRight))
                path.addLine(to: bottomRight.position)
                let bottomLeft = (name: "Bottom Left", position: self.convert(point: barcode.bottomLeft))
                path.addLine(to: bottomLeft.position)
                path.addLine(to: topLeft.position)
                
                for i in 0 ..< featurePointCloud.count {
                    let featurePointPosition = SCNVector3(x: featurePointCloud.points[i].x, y: featurePointCloud.points[i].y, z: featurePointCloud.points[i].z)
                    
                    //    v1 --------------v0
                    //    |             __/
                    //    |          __/
                    //    |       __/
                    //    |    __/
                    //    | __/
                    //    v2
                    
                    self.showNodeAtQR(featurePointPosition: featurePointPosition, qrPosition: topRight)
                    self.showNodeAtQR(featurePointPosition: featurePointPosition, qrPosition: topLeft)
                    self.showNodeAtQR(featurePointPosition: featurePointPosition, qrPosition: bottomLeft)
                }
            }
            self.drawLayer.path = path
        }
    }
    private func convert(point: CGPoint) -> CGPoint {
        return CGPoint(x: point.x * view.bounds.size.width,
                       y: (1 - point.y) * view.bounds.size.height)
    }
    
    private func showNodeAtQR(featurePointPosition: SCNVector3, qrPosition: (name: String, position: CGPoint)) {
        
        let featurePointScreenXPosition = self.sceneView.projectPoint(featurePointPosition).x
        let featurePointScreenYPosition = self.sceneView.projectPoint(featurePointPosition).y
        let delta: Float = 10
        
        if (featurePointScreenXPosition > (Float(qrPosition.position.x) - delta) && featurePointScreenXPosition <= (Float(qrPosition.position.x) + delta) && featurePointScreenYPosition > (Float(qrPosition.position.y) - delta) && featurePointScreenYPosition <= (Float(qrPosition.position.y) + delta)) {
            for node in nodes {
                if node.name == qrPosition.name {
                    node.removeFromParentNode()
                    node.position = featurePointPosition
                    self.sceneView.scene.rootNode.addChildNode(node)
                }
                if node.name == "Bottom Left" {
                    let constraint = SCNLookAtConstraint.init(target: self.sceneView.scene.rootNode.childNode(withName: "Top Left", recursively: false))
                    constraint.worldUp = SCNUtils.getNormal(v0: self.topRightPointNode.position, v1: self.topLeftPointNode.position, v2:  self.bottomLeftPointNode.position)
                    node.constraints = [constraint]
                }
            }
        }
    }
    
    @objc private func addEarthNode() {
        self.sceneView.scene.rootNode.childNode(withName: "Bottom Left", recursively: false)?.addChildNode(self.axesNode)
        self.sceneView.scene.rootNode.childNode(withName: "Bottom Left", recursively: false)?.addChildNode(self.earthNode)
    }
    
    // MARK: - Focus Square
    var focusSquare: FocusSquare?
    
    func setupFocusSquare() {
        focusSquare?.isHidden = true
        focusSquare?.removeFromParentNode()
        focusSquare = FocusSquare()
        sceneView.scene.rootNode.addChildNode(focusSquare!)
        
        //textManager.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
    }
    
    func updateFocusSquare() {
        guard let screenCenter = screenCenter else { return }
        focusSquare?.unhide()
        
        let (worldPos, planeAnchor, _) = worldPositionFromScreenPosition(screenCenter, objectPos: focusSquare?.position)
        if let worldPos = worldPos {
            focusSquare?.update(for: worldPos, planeAnchor: planeAnchor, camera: self.session.currentFrame?.camera)
            //textManager.cancelScheduledMessage(forType: .focusSquare)
        }
        
        
        guard let pixelBuffer = self.session.currentFrame?.capturedImage else { return }
        
        var requestOptions: [VNImageOption: Any] = [:]
        
        requestOptions = [.cameraIntrinsics: self.session.currentFrame?.camera.intrinsics as Any]
        
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: 6, options: requestOptions)
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    var dragOnInfinitePlanesEnabled = false
    
    func worldPositionFromScreenPosition(_ position: CGPoint,
                                         objectPos: SCNVector3?,
                                         infinitePlane: Bool = false) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {
        
        // -------------------------------------------------------------------------------
        // 1. Always do a hit test against exisiting plane anchors first.
        //    (If any such anchors exist & only within their extents.)
        
        let planeHitTestResults = sceneView.hitTest(position, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {
            
            let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
            let planeAnchor = result.anchor
            
            // Return immediately - this is the best possible outcome.
            return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
        }
        
        // -------------------------------------------------------------------------------
        // 2. Collect more information about the environment by hit testing against
        //    the feature point cloud, but do not return the result yet.
        
        var featureHitTestPosition: SCNVector3?
        var highQualityFeatureHitTestResult = false
        
        let highQualityfeatureHitTestResults = sceneView.hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)
        
        if !highQualityfeatureHitTestResults.isEmpty {
            let result = highQualityfeatureHitTestResults[0]
            featureHitTestPosition = result.position
            highQualityFeatureHitTestResult = true
        }
        
        // -------------------------------------------------------------------------------
        // 3. If desired or necessary (no good feature hit test result): Hit test
        //    against an infinite, horizontal plane (ignoring the real world).
        
        if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {
            
            let pointOnPlane = objectPos ?? SCNVector3Zero
            
            let pointOnInfinitePlane = sceneView.hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
            if pointOnInfinitePlane != nil {
                return (pointOnInfinitePlane, nil, true)
            }
        }
        
        // -------------------------------------------------------------------------------
        // 4. If available, return the result of the hit test against high quality
        //    features if the hit tests against infinite planes were skipped or no
        //    infinite plane was hit.
        
        if highQualityFeatureHitTestResult {
            return (featureHitTestPosition, nil, false)
        }
        
        // -------------------------------------------------------------------------------
        // 5. As a last resort, perform a second, unfiltered hit test against features.
        //    If there are no features in the scene, the result returned here will be nil.
        
        let unfilteredFeatureHitTestResults = sceneView.hitTestWithFeatures(position)
        if !unfilteredFeatureHitTestResults.isEmpty {
            let result = unfilteredFeatureHitTestResults[0]
            return (result.position, nil, false)
        }
        
        return (nil, nil, false)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        //refreshFeaturePoints()
        
        DispatchQueue.main.async {
            self.updateFocusSquare()
        }
    }
}
