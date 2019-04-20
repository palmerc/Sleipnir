import Foundation



public struct ImageContainer {
    let identifier: Int
    let width: Int
    let height: Int
    let pixelValues: [UInt8]

    public init(identifier: Int, width: Int, height: Int, pixelValues: [UInt8])
    {
        self.identifier = identifier
        self.width = width
        self.height = height
        self.pixelValues = pixelValues
    }
}
