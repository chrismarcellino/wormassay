/*
* Copyright 2017 Huy Cuong Nguyen
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

#include "MultiFormatWriter.h"
#include "BitMatrix.h"
#include "aztec/AZWriter.h"
#include "datamatrix/DMWriter.h"
#include "pdf417/PDFWriter.h"
#include "qrcode/QRWriter.h"
#include "qrcode/QRErrorCorrectionLevel.h"
#include "oned/ODCodabarWriter.h"
#include "oned/ODCode39Writer.h"
#include "oned/ODCode93Writer.h"
#include "oned/ODCode128Writer.h"
#include "oned/ODEAN8Writer.h"
#include "oned/ODEAN13Writer.h"
#include "oned/ODITFWriter.h"
#include "oned/ODUPCAWriter.h"
#include "oned/ODUPCEWriter.h"

#include <stdexcept>

namespace ZXing {

BitMatrix
MultiFormatWriter::encode(const std::wstring& contents, int width, int height) const
{
	auto exec0 = [&](auto&& writer) {
		if (_margin >=0)
			writer.setMargin(_margin);
		return writer.encode(contents, width, height);
	};

	auto AztecEccLevel = [&](Aztec::Writer& writer, int eccLevel) { writer.setEccPercent(eccLevel * 100 / 8); };
	auto Pdf417EccLevel = [&](Pdf417::Writer& writer, int eccLevel) { writer.setErrorCorrectionLevel(eccLevel); };
	auto QRCodeEccLevel = [&](QRCode::Writer& writer, int eccLevel) {
		writer.setErrorCorrectionLevel(static_cast<QRCode::ErrorCorrectionLevel>(--eccLevel / 2));
	};

	auto exec1 = [&](auto&& writer, auto setEccLevel) {
		if (_encoding != CharacterSet::Unknown)
			writer.setEncoding(_encoding);
		if (_eccLevel >= 0 && _eccLevel <= 8)
			setEccLevel(writer, _eccLevel);
		return exec0(std::move(writer));
	};

	switch (_format) {
	case BarcodeFormat::AZTEC: return exec1(Aztec::Writer(), AztecEccLevel);
	case BarcodeFormat::DATA_MATRIX: return exec0(DataMatrix::Writer());
	case BarcodeFormat::PDF_417: return exec1(Pdf417::Writer(), Pdf417EccLevel);
	case BarcodeFormat::QR_CODE: return exec1(QRCode::Writer(), QRCodeEccLevel);
	case BarcodeFormat::CODABAR: return exec0(OneD::CodabarWriter());
	case BarcodeFormat::CODE_39: return exec0(OneD::Code39Writer());
	case BarcodeFormat::CODE_93: return exec0(OneD::Code93Writer());
	case BarcodeFormat::CODE_128: return exec0(OneD::Code128Writer());
	case BarcodeFormat::EAN_8: return exec0(OneD::EAN8Writer());
	case BarcodeFormat::EAN_13: return exec0(OneD::EAN13Writer());
	case BarcodeFormat::ITF: return exec0(OneD::ITFWriter());
	case BarcodeFormat::UPC_A: return exec0(OneD::UPCAWriter());
	case BarcodeFormat::UPC_E: return exec0(OneD::UPCEWriter());
	default: throw std::invalid_argument(std::string("Unsupported format: ") + ToString(_format));
	}
}

} // ZXing
