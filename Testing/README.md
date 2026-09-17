# Stage Test Data and Tests

This is the canonical location for all staged validation files. Keep stage tests and fixtures here, outside the Flutter app's `lib` and `test` folders.

## Layout

- `stage1/` - AES crypto tests
- `stage2/` - tone mapping and Goertzel tests
- `stage3/` - in-memory pipeline tests and WAV fixture
- `stage4/` - hardware/DSP validation tests; phone procedure is manual
- `stage5/` - acoustic pipeline/UI validation tests
- `aes_crypto_vectors.json` - Stage 1 test vectors

Run the automated stages from the Flutter project directory:

```sh
flutter test ../Testing/stage1/aes_crypto_test.dart \
	../Testing/stage2/tone_mapping_test.dart \
	../Testing/stage3/pipeline_test.dart
```

Do not recreate a second `testing/` directory under the Flutter project.

The Stage 4 phone procedure lives at `working codes/docs/stage4_test_procedure.md`; it cannot be automated in Codespaces.

The crypto implementation uses a fixed zero IV and no padding by design.
