import UIKit
import Foundation

class ExciseStohasticVerifier {
    private var candidates = [String]()
    private var charCandidates = [String](repeating: "", count: 9)
    public var bottomProbabilityThreshold: Float = 0.4
    public var minimumCandidatesCount: Int = 2
    public var lastPossibleNumber: String = ""
    public var charProbability = [Double](repeating: 0.0, count: 9)
    
    init(minimumCandidatesCount: Int, bottomProbabilityThreshold: Float) {
        self.minimumCandidatesCount = minimumCandidatesCount
        self.bottomProbabilityThreshold = bottomProbabilityThreshold
    }
    
    private func calculatePenalty(x: Int) -> Double {
        var penalty: Double = 0.0;
        // Use logistic function or sigmoid curve for penalty (https://en.wikipedia.org/wiki/Sigmoid_function)
        if (x > 0){
            penalty = Double(1/(1+exp(Float(6-x)/Float(3)))) // Reserved logarythm penalty log10(len+1)/(4*log10(2))
        }
    
        if (penalty < 0){
            penalty = 0.0
        }
    
        if (penalty > 0.96){
            penalty = 1.0
        }
    
        return penalty
    }
    
    private func correctProbability(penalty: Double, realProbability: Double) -> Double {
        let result: Double = penalty * realProbability;
        
        if (Float(result) < bottomProbabilityThreshold){
            return 0.0
        }
        
        return (result - Double(bottomProbabilityThreshold)) / (1.0 - Double(bottomProbabilityThreshold))
    }
    
    private func getMaxOccuringChar(str: String) -> (Character, Double) {
        var count = [Int](repeating: 0, count: 256)
    
        let len = str.count
        let penalty = calculatePenalty(x: len);
        for i in 0 ..< len {
            count[str[i].code()] += 1
        }
    
        var max = -1
        var result: Character = " "
    
        for i in 0 ..< len {
            if (max < count[str[i].code()]) {
                max = count[str[i].code()]
                result = str[i]
            }
        }
    
        let realProbability = Double(max) / Double(len);
    
        let showedProbability = correctProbability(penalty: penalty, realProbability: realProbability);
    
        return (result, showedProbability)
    }
    
    public func clearAccumulator() {
        charProbability = [Double](repeating: 0.0, count: 9)
        lastPossibleNumber = ""
        candidates = [String]()
        charCandidates = [String](repeating: "", count: 9)
    }
    
    public func calculatePossibleNumber() -> String {
        
        if (candidates.count < minimumCandidatesCount) {
            lastPossibleNumber = ""
            return ""
        }
        
        var possibleNumber = ""
        
        // Calculations
        for i in 0...8 {
            if !charCandidates[i].isEmpty {
                let prediction = getMaxOccuringChar(str: charCandidates[i]);
                possibleNumber.append(prediction.0);
                charProbability[i] = prediction.1;
            }
        }
        lastPossibleNumber = possibleNumber
        
        return possibleNumber
    }
    
    public func getCandidatesCount() -> Int{
        return candidates.count
    }
    
    public func lastAddedNumber() -> String {
        return candidates.last ?? ""
    }
    
    public func addNumber(str: String) -> Bool {

        if (str.count > 8){
            candidates.append(str);
            for j in 1...9 {
                charCandidates[9 - j] += String(str[str.count - j]);
            }
            return true
        }
    
        return false
    }
}
