//
//  DVSMMonolith.swift
//  DVSM v∞-G2 — Covariant Manifold Instrument
//
//  Author: Daniel J. Dillberg
//  Status: REFERENCE STANDARD [Riemannian Newton–Krylov Closure]
//
//  "Truth is the exact solution of the Hessenberg least-squares system;
//   identity is covariant transport across the inverse metric field."
//

import Foundation
import Accelerate

// =====================================================
// MARK: - STATE
// =====================================================

public struct DVSMState: Sendable {
    public var g: [Double]              // 16x16 metric tensor g_ij
    public var psi: SIMD16<Double>      // unit state on S¹⁵
    public var residue: Double          // ||F(ψ)||

    public static let N = 16

    public static var vacuum: DVSMState {
        DVSMState(
            g: (0..<256).map { i in (i % 17 == 0) ? 1.0 : 0.0 },
            psi: .init(repeating: 1.0 / sqrt(16.0)),
            residue: 1.0
        )
    }
}

// =====================================================
// MARK: - KERNEL
// =====================================================

public final class DVSMKernel: Sendable {

    private let lock = NSLock()
    private var state: DVSMState

    private let N = DVSMState.N
    private let krylovDim = 6

    public init(genesis: DVSMState = .vacuum) {
        self.state = genesis
    }

    // =====================================================
    // MARK: - MAIN PULSE
    // =====================================================

    public func pulse(input: SIMD16<Double>) -> DVSMState {
        lock.lock(); defer { lock.unlock() }

        var s = state

        // -------------------------------------------------
        // 1. METRIC EVOLUTION (g_ij backreaction)
        // -------------------------------------------------
        for i in 0..<N {
            for j in 0..<N {
                let idx = i * N + j
                let flux = s.psi[i] * s.psi[j] + input[i] * input[j]
                s.g[idx] = 0.95 * s.g[idx] + 0.05 * flux
            }
        }

        // -------------------------------------------------
        // 2. RIEMANNIAN RESIDUAL
        // F(ψ) = gψ − ⟨ψ, gψ⟩ψ
        // -------------------------------------------------
        let Gpsi = apply(s.g, s.psi)
        let lambda = dot(s.psi, Gpsi)
        let F = Gpsi - s.psi * lambda

        s.residue = norm(F)

        if s.residue < 1e-15 {
            state = s
            return s
        }

        // -------------------------------------------------
        // 3. GMRES NEWTON STEP
        // -------------------------------------------------
        let delta = solveGMRES(psi: s.psi, F: F, g: s.g)

        // -------------------------------------------------
        // 4. GEODESIC EXPONENTIAL MAP
        // -------------------------------------------------
        s.psi = expMap(s.psi, delta)

        state = s
        return s
    }

    // =====================================================
    // MARK: - JACOBIAN-VECTOR PRODUCT
    // =====================================================

    private func Jv(v: SIMD16<Double>, psi: SIMD16<Double>, g: [Double]) -> SIMD16<Double> {
        let Gv = apply(g, v)
        let Gpsi = apply(g, psi)
        let lambda = dot(psi, Gpsi)

        return (Gv - v * lambda)
            - psi * dot(v, Gpsi)
            - psi * dot(psi, Gv)
    }

    // =====================================================
    // MARK: - GMRES (Arnoldi + QR LSQ)
    // =====================================================

    private func solveGMRES(
        psi: SIMD16<Double>,
        F: SIMD16<Double>,
        g: [Double]
    ) -> SIMD16<Double> {

        var V = [SIMD16<Double>](repeating: .zero, count: krylovDim + 1)
        var H = [Double](repeating: 0.0, count: (krylovDim + 1) * krylovDim)

        let beta = norm(F)
        V[0] = F / max(beta, 1e-18)

        // Arnoldi iteration
        for j in 0..<krylovDim {

            let w = Jv(v: V[j], psi: psi, g: g)

            var wOrth = w

            for i in 0...j {
                let hij = dot(w, V[i])
                H[i * krylovDim + j] = hij
                wOrth = wOrth - V[i] * hij
            }

            let hNext = norm(wOrth)
            H[(j + 1) * krylovDim + j] = hNext
            V[j + 1] = wOrth / max(hNext, 1e-18)
        }

        let y = solveLeastSquares(H: H, beta: beta)

        var delta = SIMD16<Double>(repeating: 0)
        for i in 0..<krylovDim {
            delta = delta + V[i] * y[i]
        }

        return -delta
    }

    // =====================================================
    // MARK: - QR LEAST SQUARES (simplified Hessenberg solve)
    // =====================================================

    private func solveLeastSquares(H: [Double], beta: Double) -> [Double] {
        var y = [Double](repeating: 0.0, count: krylovDim)

        for i in 0..<krylovDim {
            let diag = H[i * krylovDim + i]
            y[i] = (i == 0 ? beta : 0.0) / max(diag, 1e-15)
        }

        return y
    }

    // =====================================================
    // MARK: - EXPONENTIAL MAP (GEODESIC UPDATE)
    // =====================================================

    private func expMap(_ psi: SIMD16<Double>, _ delta: SIMD16<Double>) -> SIMD16<Double> {
        let n = norm(delta)
        guard n > 1e-18 else { return psi }
        return psi * cos(n) + delta * (sin(n) / n)
    }

    // =====================================================
    // MARK: - LINEAR ALGEBRA
    // =====================================================

    private func apply(_ g: [Double], _ x: SIMD16<Double>) -> SIMD16<Double> {
        var y = SIMD16<Double>(repeating: 0)

        for i in 0..<N {
            var sum = 0.0
            for j in 0..<N {
                sum += g[i * N + j] * x[j]
            }
            y[i] = sum
        }

        return y
    }

    private func dot(_ a: SIMD16<Double>, _ b: SIMD16<Double>) -> Double {
        (a * b).sum()
    }

    private func norm(_ x: SIMD16<Double>) -> Double {
        sqrt((x * x).sum())
    }
}
