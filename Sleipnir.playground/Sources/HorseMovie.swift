import Cocoa


public protocol Movie
{
    func nextFrame() -> ImageContainer?
}



open class HorseMovie: Movie {
    var horseFrameNames: [String]?
    var currentHorseFrame: Int

    public init()
    {
        self.currentHorseFrame = 0

        let numberOfFrames = 12;
        var horseFrameNames = [String]()
        for index in 1 ... numberOfFrames {
            let filename = String(format: "Horse%02d", index)
            horseFrameNames.append(filename)
        }

        print("\(horseFrameNames)")
        self.horseFrameNames = horseFrameNames
    }

    public func nextFrame() -> ImageContainer?
    {
        var imageContainer: ImageContainer?
        if let horseFrameNames = self.horseFrameNames {
            let filename = horseFrameNames[self.currentHorseFrame]
            let image = NSImage(named: filename)
            let imageRef = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let (pixelValues, width, height) = ImageHelper.pixelValues(cgImage: imageRef)
            if let pixelValues = pixelValues {
                imageContainer = ImageContainer(identifier: self.currentHorseFrame, width: width, height: height, pixelValues: pixelValues)
                if self.currentHorseFrame < horseFrameNames.count - 2 {
                    self.currentHorseFrame += 1;
                } else {
                    self.currentHorseFrame = 0;
                }
            }
        }
        
        return imageContainer;
    }
}
