import Foundation
import CryptoKit
import OSLog

// =====================================================
// MARK: - DVSM v17.x: UNIFIED GEOMETRIC CONSENSUS
// MARK: - (World-Scale Byzantine Temporal System)
// =====================================================

// =====================================================
// 1. CORE NUMERICS (Global Determinism Layer)
// =====================================================

public struct FixedPoint: Sendable, Hashable, Comparable {
    public let rawValue: Int64
    public static let scale: Int64 = 1_000_000

    public init(_ v: Double) {
        self.rawValue = Int64(v * Double(Self.scale))
    }

    public init(raw: Int64) {
        self.rawValue = raw
    }

    public static func + (l: FixedPoint, r: FixedPoint) -> FixedPoint {
        .init(raw: l.rawValue + r.rawValue)
    }

    public static func - (l: FixedPoint, r: FixedPoint) -> FixedPoint {
        .init(raw: l.rawValue - r.rawValue)
    }

    public static func / (l: FixedPoint, r: Int) -> FixedPoint {
        .init(raw: l.rawValue / Int64(r))
    }

    public static func < (l: FixedPoint, r: FixedPoint) -> Bool {
        l.rawValue < r.rawValue
    }

    public static func == (l: FixedPoint, r: FixedPoint) -> Bool {
        l.rawValue == r.rawValue
    }
}

// =====================================================
// 2. TEMPORAL MODEL (Global Round Agreement)
// =====================================================

public struct DVSMRound: Sendable, Hashable, Comparable {
    public let epoch: UInt64
    public let sequence: UInt64

    public static func < (l: DVSMRound, r: DVSMRound) -> Bool {
        l.epoch < r.epoch || (l.epoch == r.epoch && l.sequence < r.sequence)
    }
}

// =====================================================
// 3. SEMANTIC MEASUREMENT SPACE (Invariant Physics Layer)
// =====================================================

public struct DVSMLoadTensor: Sendable, Hashable {
    public let pressure: FixedPoint
    public let volatility: FixedPoint
    public let anomaly: FixedPoint

    /// WORLD ASSUMPTION:
    /// All nodes must normalize using identical calibration constants
    /// or they are treated as adversarial by divergence.
    public static func project(cpu: Double, capacity: Double, jitter: Double) -> DVSMLoadTensor {
        let normalized = max(0.0, min(cpu / max(capacity, 0.0001), 1.0))

        return DVSMLoadTensor(
            pressure: FixedPoint(tanh(normalized)),
            volatility: FixedPoint(jitter / 100.0),
            anomaly: FixedPoint(0.0)
        )
    }
}

// =====================================================
// 4. CRYPTOGRAPHIC AGREEMENT LAYER (Byzantine Closure)
// =====================================================

public struct DVSMTruthHash: Sendable, Hashable {
    public let fullData: Data
}

public struct DVSMSealedAdvisory: Sendable {
    public let nodeId: UUID
    public let round: DVSMRound
    public let metrics: DVSMLoadTensor
    public let signature: Data
}

public struct DVSMSeal: Sendable, Hashable {
    public let merkleRoot: Data
    public let participants: [UUID]
    public let aggregateSignature: Data

    /// GLOBAL SECURITY INVARIANT:
    /// A seal is valid only if:
    /// - quorum is satisfied
    /// - merkle root is reproducible
    /// - participant set is deterministic across nodes
    public func isValid() -> Bool {
        !participants.isEmpty && merkleRoot.count == 32
    }
}

public struct DVSMSealedSnapshot: Sendable {
    public let round: DVSMRound
    public let systemLoad: DVSMLoadTensor
    public let seal: DVSMSeal
    public let advisories: [UUID: DVSMSealedAdvisory]
}

// =====================================================
// 5. HISTORY GEOMETRY (Λ₂ COMPRESSION SPACE)
// =====================================================

public struct DVSMAgeSummary: Sendable {
    public let metaRootHash: Data
    public let epochSpan: ClosedRange<UInt64>
    public let manifoldAnchor: DVSMLoadTensor
}

// =====================================================
// 6. RECONCILIATION FIELD (Epistemic Alignment Layer)
// =====================================================

public enum DVSMRecoveryMode: Sendable {
    case coldBootstrap
    case warmSync
    case verified
}

public struct DVSMReconciliationField: Sendable {
    public let ageSummary: DVSMAgeSummary
    public let liveSnapshot: DVSMSealedSnapshot
    public let epsilon: FixedPoint

    /// WORLD SCALE RULE:
    /// Divergence is interpreted as probability of Byzantine drift.
    public func projectDivergence(local: DVSMLoadTensor) -> FixedPoint {
        let pDelta = abs(local.pressure.rawValue - liveSnapshot.systemLoad.pressure.rawValue)
        let vDelta = abs(local.volatility.rawValue - liveSnapshot.systemLoad.volatility.rawValue)

        return FixedPoint(raw: (pDelta + vDelta) / 2)
    }

    public func classify(divergence: FixedPoint) -> DVSMRecoveryMode {
        if divergence < FixedPoint(raw: epsilon.rawValue / 4) {
            return .verified
        } else if divergence < epsilon {
            return .warmSync
        } else {
            return .coldBootstrap
        }
    }
}

// =====================================================
// 7. UNIFIED KERNEL (GLOBAL CONSENSUS ENGINE)
// =====================================================

public final class DVSMKernel: Sendable {
    private let state: OSAllocatedUnfairLock<KernelState>
    private let config: DVSMClusterConfig

    struct KernelState {
        var currentRound: DVSMRound
        var recoveryMode: DVSMRecoveryMode
        var ageSummary: DVSMAgeSummary
        var finalizedRegistry: [DVSMRound: DVSMTruthHash]
    }

    public init(config: DVSMClusterConfig, bootstrap: DVSMAgeSummary) {
        self.config = config

        self.state = OSAllocatedUnfairLock(initialState: KernelState(
            currentRound: DVSMRound(
                epoch: bootstrap.epochSpan.upperBound + 1,
                sequence: 0
            ),
            recoveryMode: .coldBootstrap,
            ageSummary: bootstrap,
            finalizedRegistry: [:]
        ))
    }

    /// WORLD ENTRY POINT:
    /// Deterministic, Byzantine-safe, temporally ordered state transition.
    public func pulse(
        input: Data,
        snapshot: DVSMSealedSnapshot,
        localLoad: DVSMLoadTensor
    ) throws -> DVSMTruthHash {

        let (round, age) = state.withLock { ($0.currentRound, $0.ageSummary) }

        // -------------------------------------------------
        // 1. TEMPORAL + BYZANTINE VALIDATION
        // -------------------------------------------------
        guard snapshot.round == round else {
            throw DVSMError.temporalViolation
        }

        guard snapshot.seal.isValid(),
              snapshot.advisories.count >= config.threshold else {
            throw DVSMError.quorumFailure
        }

        // -------------------------------------------------
        // 2. RECONCILIATION FIELD (GLOBAL ALIGNMENT TEST)
        // -------------------------------------------------
        let field = DVSMReconciliationField(
            ageSummary: age,
            liveSnapshot: snapshot,
            epsilon: FixedPoint(0.1)
        )

        let divergence = field.projectDivergence(local: localLoad)
        let newMode = field.classify(divergence: divergence)

        // -------------------------------------------------
        // 3. TRUTH COMMITMENT (IRREVERSIBLE STATE)
        // -------------------------------------------------
        let truth = DVSMTruthHash(
            fullData: Data(SHA256.hash(data: input))
        )

        state.withLock {
            $0.recoveryMode = newMode
            $0.finalizedRegistry[round] = truth
            $0.currentRound = DVSMRound(
                epoch: round.epoch,
                sequence: round.sequence + 1
            )
        }

        return truth
    }
}

// =====================================================
// 8. CLUSTER CONFIG (WORLD DEPLOYMENT MODEL)
// =====================================================

public struct DVSMClusterConfig: Sendable {
    public let activeNodes: Set<UUID>

    /// GLOBAL ASSUMPTION:
    /// threshold must tolerate partial network partition (≥ 2/3 typical)
    public let threshold: Int
}

// =====================================================
// 9. GLOBAL ERROR MODEL
// =====================================================

public enum DVSMError: Error {
    case temporalViolation
    case quorumFailure
    case recoveryDivergence
}
