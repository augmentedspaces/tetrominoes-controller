//
//  ContentView.swift
//  TetrominoesController
//
//  Created by Nien Lam on 9/21/21.
//  Copyright © 2021 Line Break, LLC. All rights reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Combine


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    
    @Published var positionLocked = false
    
    enum UISignal {
        case straightSelected
        case squareSelected
        case tSelected
        case lSelected
        case skewSelected

        case moveLeft
        case moveRight

        case rotateCCW
        case rotateCW

        case lockPosition
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
            
            // Left / Right controls.
            HStack {
                HStack {
                    Button {
                        viewModel.uiSignal.send(.moveLeft)
                    } label: {
                        buttonIcon("arrow.left", color: .blue)
                    }
                }

                HStack {
                    Button {
                        viewModel.uiSignal.send(.moveRight)
                    } label: {
                        buttonIcon("arrow.right", color: .blue)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 30)


            // Rotation controls.
            HStack {
                HStack {
                    Button {
                        viewModel.uiSignal.send(.rotateCCW)
                    } label: {
                        buttonIcon("rotate.left", color: .red)
                    }
                }

                HStack {
                    Button {
                        viewModel.uiSignal.send(.rotateCW)
                    } label: {
                        buttonIcon("rotate.right", color: .red)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, 30)

            // Lock release button.
            Button {
                viewModel.uiSignal.send(.lockPosition)
            } label: {
                Label("Lock Position", systemImage: "target")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
                    .opacity(viewModel.positionLocked ? 0.25 : 1.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 30)


            // Bottom buttons.
            HStack {
                Button {
                    viewModel.uiSignal.send(.straightSelected)
                } label: {
                    tetrominoIcon("straight", color: Color(red: 0, green: 1, blue: 1))
                }
                
                Button {
                    viewModel.uiSignal.send(.squareSelected)
                } label: {
                    tetrominoIcon("square", color: .yellow)
                }
                
                Button {
                    viewModel.uiSignal.send(.tSelected)
                } label: {
                    tetrominoIcon("t", color: .purple)
                }
                
                Button {
                    viewModel.uiSignal.send(.lSelected)
                } label: {
                    tetrominoIcon("l", color: .orange)
                }
                
                Button {
                    viewModel.uiSignal.send(.skewSelected)
                } label: {
                    tetrominoIcon("skew", color: .green)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
    
    // Helper methods for rendering icons.
    
    func tetrominoIcon(_ image: String, color: Color) -> some View {
        Image(image)
            .resizable()
            .padding(3)
            .frame(width: 44, height: 44)
            .background(color)
            .cornerRadius(5)
    }

    func buttonIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .resizable()
            .padding(10)
            .frame(width: 44, height: 44)
            .foregroundColor(.white)
            .background(color)
            .cornerRadius(5)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var originAnchor: AnchorEntity!
    var subscriptions = Set<AnyCancellable>()
    
    // Empty entity for cursor.
    var cursor: Entity!
    
    // Scene lights.
    var directionalLight: DirectionalLight!
    

    // Reference to entity pieces.
    // This needs to be set in the setup.
    var straightPiece: Entity!
    var squarePiece: Entity!
    var tPiece: Entity!
    var lPiece: Entity!
    var skewPiece: Entity!
    
    // The selected tetromino.
    var activeTetromino: Entity?

    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        
        setupEntities()

        disablePieces()
    }
    
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            if !self.viewModel.positionLocked {
                self.updateCursor()
            }
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
    }
    
    // Hide/Show active tetromino & process controls.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .straightSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            straightPiece.isEnabled = true
            activeTetromino = straightPiece
        case .squareSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            squarePiece.isEnabled = true
            activeTetromino = squarePiece
        case .tSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            tPiece.isEnabled = true
            activeTetromino = tPiece
        case .lSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            lPiece.isEnabled = true
            activeTetromino = lPiece
        case .skewSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            skewPiece.isEnabled = true
            activeTetromino = skewPiece
        case .lockPosition:
            disablePieces()
            viewModel.positionLocked.toggle()
        case .moveLeft:
            moveLeftPressed()
        case .moveRight:
            moveRightPressed()
        case .rotateCCW:
            rotateCCWPressed()
        case .rotateCW:
            rotateCWPressed()
        }
    }
    
    func disablePieces() {
        straightPiece.isEnabled  = false
        squarePiece.isEnabled    = false
        tPiece.isEnabled         = false
        lPiece.isEnabled         = false
        skewPiece.isEnabled      = false
    }
    
    func clearActiveTetrominoTransform() {
        activeTetromino?.transform = Transform.identity
    }
    
    // Move cursor to plane detected.
    func updateCursor() {
        // Raycast to get cursor position.
        let results = raycast(from: center,
                              allowing: .existingPlaneGeometry,
                              alignment: .any)
        
        // Move cursor to position if hitting plane.
        if let result = results.first {
            cursor.isEnabled = true
            cursor.move(to: result.worldTransform, relativeTo: originAnchor)
        } else {
            cursor.isEnabled = false
        }
    }
    
    func setupEntities() {
        // Create an anchor at scene origin.
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)
        
        // Create and add empty cursor entity to origin anchor.
        cursor = Entity()
        originAnchor.addChild(cursor)
        
        // Add directional light.
        directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        directionalLight.look(at: [0,0,0], from: [1, 1.1, 1.3], relativeTo: originAnchor)
        directionalLight.shadow = DirectionalLightComponent.Shadow(maximumDistance: 0.5, depthBias: 2)
        originAnchor.addChild(directionalLight)

        // Add checkerboard plane.
        var checkerBoardMaterial = PhysicallyBasedMaterial()
        checkerBoardMaterial.baseColor.texture = .init(try! .load(named: "checker-board.png"))
        let checkerBoardPlane = ModelEntity(mesh: .generatePlane(width: 0.5, depth: 0.5), materials: [checkerBoardMaterial])
        cursor.addChild(checkerBoardPlane)

        // Create an relative origin entity above the checkerboard.
        let relativeOrigin = Entity()
        relativeOrigin.position.x = 0.05 / 2
        relativeOrigin.position.z = 0.05 / 2
        relativeOrigin.position.y = 0.05 * 2.5
        cursor.addChild(relativeOrigin)


        // TODO: Refactor code using TetrominoEntity Classes. ////////////////////////////////////////////

        let boxSize: Float       = 0.05
        let cornerRadius: Float  = 0.002
        let boxMesh              = MeshResource.generateBox(size: boxSize, cornerRadius: cornerRadius)

        let cyanMaterial    = SimpleMaterial(color: .cyan, isMetallic: false)
        straightPiece =  ModelEntity(mesh: boxMesh, materials: [cyanMaterial])
        relativeOrigin.addChild(straightPiece)

        let yellowMaterial  = SimpleMaterial(color: .yellow, isMetallic: false)
        squarePiece = ModelEntity(mesh: boxMesh, materials: [yellowMaterial])
        relativeOrigin.addChild(squarePiece)

        let purpleMaterial  = SimpleMaterial(color: .purple, isMetallic: false)
        tPiece = ModelEntity(mesh: boxMesh, materials: [purpleMaterial])
        relativeOrigin.addChild(tPiece)

        let orangeMaterial  = SimpleMaterial(color: .orange, isMetallic: false)
        lPiece = ModelEntity(mesh: boxMesh, materials: [orangeMaterial])
        relativeOrigin.addChild(lPiece)

        let greenMaterial   = SimpleMaterial(color: .green, isMetallic: false)
        skewPiece = ModelEntity(mesh: boxMesh, materials: [greenMaterial])
        relativeOrigin.addChild(skewPiece)
        
        //////////////////////////////////////////////////////////////////////////////////////////////////
    }


    // TODO: Implement controls to move and rotate tetromino.
    //
    // IMPORTANT: Use optional activeTetromino variable for movement and rotation.
    //
    // e.g. activeTetromino?.position.x
    
    func moveLeftPressed() {
        print("🔺 Did press move left")

    }

    func moveRightPressed() {
        print("🔺 Did press move right")

    }

    func rotateCCWPressed() {
        print("🔺 Did press rotate CCW")

    }

    func rotateCWPressed() {
        print("🔺 Did press rotate CW")

    }
}


// TODO: Design a subclass of Entity for creating a tetromino entity.

class TetrominoEntity: Entity {

    // Define inputs to class.
    init(someInputA: String, someInputB: Int) {
        super.init()


        // Create and position ModelEntity boxes.
        
        

        // Add modelEntity to 'self' which is an entity.

        /*
        self.addChild(modelEntity)
         */
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
}
