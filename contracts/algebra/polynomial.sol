// SPDX-License-Identifier: MIT OR Apache-2.0
//---------------------------------------------------------------------------//
// Copyright (c) 2021 Mikhail Komarov <nemo@nil.foundation>
// Copyright (c) 2021 Ilias Khairullin <ilias@nil.foundation>
// Copyright (c) 2022 Aleksei Moskvin <alalmoskvin@nil.foundation>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//---------------------------------------------------------------------------//

pragma solidity >=0.8.4;

import "./field.sol";
import "../basic_marshalling.sol";
import "../logging.sol";

/**
 * @title Turbo Plonk polynomial evaluation
 * @dev Implementation of Turbo Plonk's polynomial evaluation algorithms
 *
 * Expected to be inherited by `TurboPlonk.sol`
 */
library polynomial {
    uint256 constant LENGTH_OCTETS = 8;

    /*
      Computes the evaluation of a polynomial f(x) = sum(a_i * x^i) on the given point.
      The coefficients of the polynomial are given in
        a_0 = coefsStart[0], ..., a_{n-1} = coefsStart[n - 1]
      where n = nCoeffs = friLastLayerDegBound. Note that coefsStart is not actually an array but
      a direct pointer.
      The function requires that n is divisible by 8.
    */
    function evaluate(uint256[] memory coeffs, uint256 point, uint256 modulus)
    internal pure returns (uint256) {
        uint256 result;
        assembly {
            let cur_coefs := add(coeffs, mul(mload(coeffs), 0x20))
            for { } gt(cur_coefs, coeffs) {} {
                result := addmod(mulmod(result, point, modulus),
                                 mload(cur_coefs), // (i - 1) * 32
                                 modulus)
                cur_coefs := sub(cur_coefs, 0x20)
            }
        }
        return result;
    }

    function evaluate_by_ptr(bytes calldata blob, uint256 offset, uint256 len, uint256 point, uint256 modulus)
    internal pure returns (uint256) {
        uint256 result;
        for (uint256 i = len; i > 0;) {
            assembly {
                result := addmod(mulmod(result, point, modulus),
                                 calldataload(add(add(blob.offset, offset), shl(0x05, sub(i, 0x01)))), // (i - 1) * 32
                                 modulus)
            }
            unchecked{ i--; }
        }
//        assembly {
//            let i := sub(add(blob.offset, add(offset, mul(len, 0x20))), 0x20)
//            let coeff := sub(add(blob.offset, offset), 0x20)
//            for { } gt(coefsPtr, coeff) {} {
//                result := addmod(mulmod(result, point, modulus), calldataload(coefsPtr), modulus)
//                coefsPtr := sub(coefsPtr, 0x20)
//            }
//        }
        return result;
    }

    function add_poly(uint256[] memory a, uint256[] memory b, uint256 modulus)
    internal pure returns (uint256[] memory result) {
        if (a.length < b.length) {
            result = new uint256[](b.length);
            assembly {
                let i := 0
                for {} lt(i, mul(mload(a), 0x20)) {
                    i := add(i, 0x20)
                } {
                    mstore(
                    add(add(result, 0x20), i),
                    addmod(mload(add(add(a, 0x20), i)), mload(add(add(b, 0x20), i)), modulus)
                    )
                }
                for {} lt(i, mul(mload(b), 0x20)) {
                    i := add(i, 0x20)
                } {
                    mstore(
                    add(add(result, 0x20), i),
                    mload(add(b, add(0x20, i)))
                    )
                }
            }
        } else {
            result = new uint256[](a.length);
            assembly {
                let i := 0
                for {} lt(i, mul(mload(b), 0x20)) {
                    i := add(i, 0x20)
                } {
                    mstore(
                    add(add(result, 0x20), i),
                    addmod(mload(add(add(a, 0x20), i)), mload(add(add(b, 0x20), i)), modulus)
                    )
                }
                for {} lt(i, mul(mload(a), 0x20)) {
                    i := add(i, 0x20)
                } {
                    mstore(
                    add(add(result, 0x20), i),
                    mload(add(a, add(0x20, i)))
                    )
                }
            }
        }
    }

    function mul_poly(uint256[] memory a, uint256[] memory b, uint256 modulus)
    internal pure returns (uint256[] memory result) {
        uint256[] memory result = new uint256[](a.length + b.length - 1);
        for (uint256 i = 0; i < b.length;) {
            for (uint256 j = 0; j < a.length;) {
                assembly {
                    mstore(add(add(result, 0x20), mul(add(j, i), 0x20)),
                           addmod(mload(add(add(result, 0x20), mul(add(j, i), 0x20))),
                                   mulmod(mload(add(add(a, 0x20), mul(j, 0x20))),
                                          mload(add(add(b, 0x20), mul(i, 0x20))), modulus),
                                   modulus)
                    )
                }
                unchecked{ j++; }
            }
            unchecked{ i++; }
        }
        return result;
    }

    function lagrange_interpolation(
        uint256[] memory xs,
        uint256[] memory fxs,
        uint256 modulus
    ) internal pure returns (uint256[] memory result) {
        require(xs.length == fxs.length);
        uint256 len = fxs.length;
        for (uint256 i = 0; i < len;) {
            uint256[] memory thisPoly = new uint256[](1);
            thisPoly[0] = 1;
            for (uint256 j = 0; j < len;) {
                if (i == j) {
                    continue;
                }
                uint256 denominator = field.fsub(xs[i], xs[j], modulus);
                uint256[] memory thisTerm = new uint256[](2);
                thisTerm[0] = field.fdiv(modulus - xs[j], denominator, modulus);
                thisTerm[1] = field.fdiv(uint256(1), denominator, modulus);
                thisPoly = mul_poly(thisPoly, thisTerm, modulus);
                unchecked{ j++; }
            }
            if (fxs.length + 1 >= i) {
                uint256[] memory multiple = new uint256[](1);
                multiple[0] = fxs[i];
                thisPoly = mul_poly(thisPoly, multiple, modulus);
            }
            result = add_poly(result, thisPoly, modulus);
            unchecked { i++; }
        }
    }

    function interpolate_evaluate_by_2_points_neg_x(uint256 x, uint256 dblXInv, uint256 fX, uint256 fMinusX,
                                                    uint256 evalPoint, uint256 modulus
    ) internal pure returns (uint256 result) {
        assembly {
            result := addmod(
                mulmod(
                    mulmod(
                        addmod(fX, sub(modulus, fMinusX), modulus),
                        dblXInv,
                        modulus
                    ),
                    addmod(evalPoint, sub(modulus, x), modulus),
                    modulus
                ),
                fX,
                modulus
            )
        }
    }

    function interpolate_evaluate_by_2_points(uint256[] memory x, uint256[] memory fx, uint256 eval_point, uint256 modulus)
    internal view returns (uint256 result) {
        require(x.length == 2, "x length is not equal to 2");
        require(fx.length == 2, "fx length is not equal to 2");
        uint256 x2_minus_x1_inv = field.inverse_static((x[1] + (modulus - x[0])) % modulus, modulus);
        assembly {
            let y2_minus_y1 := addmod(
                mload(add(fx, 0x40)),
                sub(modulus, mload(add(fx, 0x20))),
                modulus
            )
            let x3_minus_x1 := addmod(
                eval_point,
                sub(modulus, mload(add(x, 0x20))),
                modulus
            )
            result := addmod(
                mulmod(
                    mulmod(y2_minus_y1, x2_minus_x1_inv, modulus),
                    x3_minus_x1,
                    modulus
                ),
                mload(add(fx, 0x20)),
                modulus
            )
        }
    }

    function interpolate_evaluate(uint256[] memory x, uint256[] memory fx, uint256 eval_point, uint256 modulus)
    internal view returns (uint256) {
        if (x.length == 1 && fx.length == 1) {
            return fx[0];
        }
        if (x.length == 2) {
            return interpolate_evaluate_by_2_points(x, fx, eval_point, modulus);
        }
        require(false, "unsupported number of points for interpolation");
        return 0;
    }

    function interpolate_by_2_points(uint256[] memory x, uint256[] memory fx, uint256 modulus)
    internal view returns (uint256[] memory result) {
        require(x.length == 2, "x length is not equal to 2");
        require(fx.length == 2, "fx length is not equal to 2");
        uint256 x2_minus_x1_inv = field.inverse_static((x[1] + (modulus - x[0])) % modulus, modulus);
        result = new uint256[](2);
        assembly {
            let y2_minus_y1 := addmod(mload(add(fx, 0x40)), sub(modulus, mload(add(fx, 0x20))), modulus)
            let a := mulmod(y2_minus_y1, x2_minus_x1_inv, modulus)
            let a_mul_x1_neg := sub(modulus, mulmod(a, mload(add(x, 0x20)), modulus))
            let b := addmod(mload(add(fx, 0x20)), a_mul_x1_neg, modulus)
            mstore(add(result, 0x20), b)
            mstore(add(result, 0x40), a)
        }
    }

    function interpolate(uint256[] memory x, uint256[] memory fx, uint256 modulus)
    internal view returns (uint256[] memory) {
        if (x.length == 1 && fx.length == 1) {
            uint256[] memory result = new uint256[](1);
            result[0] = fx[0];
            return result;
        } else if (x.length == 2) {
            return interpolate_by_2_points(x, fx, modulus);
        } else {
            require(false, "unsupported number of points for interpolation");
        }
    }

    function interpolate_by_2_points(bytes calldata blob, uint256[] memory x, uint256 fx_offset, uint256 modulus)
    internal view returns (uint256[] memory result) {
        require(x.length == 2, "x length is not equal to 2");
        require(basic_marshalling.get_length(blob, fx_offset) == 2, "fx length is not equal to 2");
        uint256 x2_minus_x1_inv = field.inverse_static((x[1] + (modulus - x[0])) % modulus, modulus);
        result = new uint256[](2);

        assembly {
            let y2_minus_y1 := addmod(
                calldataload(
                    add(blob.offset, add(add(fx_offset, LENGTH_OCTETS), 0x20))
                ),
                sub(
                    modulus,
                    calldataload(
                        add(blob.offset, add(fx_offset, LENGTH_OCTETS))
                    )
                ),
                modulus
            )
            let a := mulmod(y2_minus_y1, x2_minus_x1_inv, modulus)
            let a_mul_x1_neg := sub(
                modulus,
                mulmod(a, mload(add(x, 0x20)), modulus)
            )
            let b := addmod(
                calldataload(add(blob.offset, add(fx_offset, LENGTH_OCTETS))),
                a_mul_x1_neg,
                modulus
            )
            mstore(add(result, 0x20), b)
            mstore(add(result, 0x40), a)
        }
    }

    function interpolate(bytes calldata blob, uint256[] memory x, uint256 fx_offset, uint256 modulus)
    internal view returns (uint256[] memory ) {
        if (x.length == 1 && basic_marshalling.get_length(blob, fx_offset) == 1) {
            uint256[] memory result = new uint256[](1);
            result[0] = basic_marshalling.get_i_uint256_from_vector(blob, fx_offset, 0);
            return result;
        } else if (x.length == 2) {
            return interpolate_by_2_points(blob, x, fx_offset, modulus);
        } else if (x.length == 3) {
            uint256[] memory result = new uint256[](3);
            uint256[] memory sub_x = new uint256[](6);
            sub_x[0] = field.fsub(x[0], x[1],modulus);
            sub_x[1] = field.fsub(x[0], x[2],modulus);
            sub_x[2] = field.fsub(x[1], x[0],modulus);
            sub_x[3] = field.fsub(x[1], x[2],modulus);
            sub_x[4] = field.fsub(x[2], x[0],modulus);
            sub_x[5] = field.fsub(x[2], x[1],modulus);
            uint256[] memory div_one = new uint256[](3);
            div_one[0] = field.fdiv(basic_marshalling.get_i_uint256_from_vector(blob, fx_offset, 0), sub_x[0], modulus);
            div_one[1] = field.fdiv(basic_marshalling.get_i_uint256_from_vector(blob, fx_offset, 1), sub_x[2], modulus);
            div_one[2] = field.fdiv(basic_marshalling.get_i_uint256_from_vector(blob, fx_offset, 2), sub_x[4], modulus);
            uint256[] memory div_two = new uint256[](3);
            div_two[0] = field.fdiv(div_one[0], sub_x[1], modulus);
            div_two[1] = field.fdiv(div_one[1], sub_x[3], modulus);
            div_two[2] = field.fdiv(div_one[2], sub_x[5], modulus);
            result[2] = field.fadd(field.fadd(div_two[0], div_two[1], modulus), div_two[2], modulus);

            uint256[] memory mul_two = new uint256[](3);
            mul_two[0] = field.fmul(div_two[0], field.fmul(x[1], x[2], modulus), modulus);
            mul_two[1] = field.fmul(div_two[1], field.fmul(x[0], x[2], modulus), modulus);
            mul_two[2] = field.fmul(div_two[2], field.fmul(x[0], x[1], modulus), modulus);
            result[0] = field.fadd(field.fadd(mul_two[0], mul_two[1], modulus), mul_two[2], modulus);

            uint256[] memory neg = new uint256[](3);
            neg[0] = field.fsub(modulus, field.fadd(x[1], x[2], modulus), modulus);
            neg[1] = field.fsub(modulus, field.fadd(x[0], x[2], modulus), modulus);
            neg[2] = field.fsub(modulus, field.fadd(x[0], x[1], modulus), modulus);

            uint256[] memory last = new uint256[](3);
            last[0] = field.fmul(div_two[0], neg[0], modulus);
            last[1] = field.fmul(div_two[1], neg[1], modulus);
            last[2] = field.fmul(div_two[2], neg[2], modulus);

            result[1] = field.fadd(field.fadd(last[0], last[1], modulus), last[2], modulus);
            return result;
//        require(false, logging.uint2decstr(result[1]));
//            require(false, logging.uint2decstr(result[0]));
        } else {
            require(false, "unsupported number of points for interpolation");
        }
    }
}
