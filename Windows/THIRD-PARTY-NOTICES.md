# Third-party components

The application embeds Newtonsoft.Json 13.0.3, distributed under the MIT license:

Copyright (c) 2007 James Newton-King

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Optional local AI downloads are installed separately into the current user's application-data directory. They are not bundled into the application or installer. Upstream projects and model terms:

- [uv](https://github.com/astral-sh/uv): MIT / Apache-2.0.
- [Python](https://www.python.org/psf/license/): Python Software Foundation license.
- [PyTorch](https://github.com/pytorch/pytorch/blob/main/LICENSE): BSD-style license; CUDA packages include additional upstream notices.
- [Pillow](https://github.com/python-pillow/Pillow/blob/main/LICENSE): HPND license.
- [Spandrel](https://github.com/chaiNNer-org/spandrel): MIT license.
- [Diffusers](https://github.com/huggingface/diffusers): Apache-2.0.
- [Transformers](https://github.com/huggingface/transformers): Apache-2.0.
- [Accelerate](https://github.com/huggingface/accelerate): Apache-2.0.
- [Hugging Face Hub](https://github.com/huggingface/huggingface_hub): Apache-2.0.
- [Hugging Face Xet](https://github.com/huggingface/xet-core): Apache-2.0; resumable model transport.
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN): BSD-3-Clause; the detail model is downloaded from the upstream release.
- [SDXL inpainting model](https://huggingface.co/diffusers/stable-diffusion-xl-1.0-inpainting-0.1): see its model card and CreativeML Open RAIL++-M license.

The .NET Framework reference-assemblies NuGet package is a build-time dependency only. Windows supplies the .NET Framework runtime.
