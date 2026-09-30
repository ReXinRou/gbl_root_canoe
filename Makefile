clean:
	rm -rf edk2/Build || true
	rm -rf edk2/Conf || true
	rm edk2/QcomModulePkg/Include/Library/ABL.h || true
	rm tools/patch_abl || true
	rm -rf dist || true
	rm -rf ./build || true
	mkdir dist
patch: clean
	gcc -O2 -o ./tools/extractfv ./tools/extractfv.c -llzma
	./tools/extractfv ./images/abl.img -o ./dist
	rm ./tools/extractfv
	mv ./dist/LinuxLoader.efi ./dist/ABL_original.efi
	gcc -o tools/patch_abl tools/patch_abl.c
	./tools/patch_abl ./dist/ABL_original.efi ./dist/ABL.efi > ./dist/patch_log.txt
	rm tools/patch_abl
	cat ./dist/patch_log.txt
build: patch
	ls -l ./dist

dist_loader:
	mkdir -p ./dist/images
	touch ./dist/images/PUT_ABL_IMAGE_HERE
	mkdir ./dist/bin
	mkdir release || true
	gcc -o ./dist/bin/extractfv ./tools/extractfv.c -llzma
	gcc -o ./dist/bin/patch_abl ./tools/patch_abl.c
	cp ./tools/build.sh ./dist
	cp ./tools/Makefile_dist ./dist/Makefile
	zip -r release/$(DIST_NAME)_linux.zip dist

dist_loader_windows:
	#build with mingw-w64
	mkdir -p ./dist/images
	touch ./dist/images/PUT_ABL_IMAGE_HERE
	mkdir -p ./dist/bin
	bash ./tools/build_extractfv_windows.sh
	x86_64-w64-mingw32-gcc -o ./dist/bin/patch_abl.exe ./tools/patch_abl.c
	cp ./tools/build.bat ./dist
	zip -r release/$(DIST_NAME)_windows.zip dist

dist_loader_android: build_patcher_android
	mkdir -p ./dist/images
	touch ./dist/images/PUT_ABL_IMAGE_HERE
	mkdir -p ./dist/bin
	mv ./dist/patch_abl_android ./dist/bin/patch_abl
	mv ./dist/extractfv_android ./dist/bin/extractfv
	cp ./tools/build.sh ./dist
	zip -r release/$(DIST_NAME)_android.zip dist

dist: build
	mkdir release
	zip -r release/$(DIST_NAME).zip dist

build_patcher_android: clean
	$(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang tools/patch_abl.c -o dist/patch_abl_android
	bash ./tools/build_extractfv_android.sh
build_module: build_patcher_android
	mv dist/patch_abl_android magisk_module/bin/patch_abl
	mv dist/extractfv_android magisk_module/bin/extractfv
	mkdir release || true
	cd magisk_module && zip -r ../release/$(DIST_NAME).zip ./
	rm magisk_module/bin/patch_abl
	rm magisk_module/bin/extractfv

test_exploit:
	@echo "This script is used to test the ABL exploit. Please make sure you tested before ota."
	@echo Please enter the Builtin Fastboot in the project. And put abl.img in the images folder. Press Enter to continue.
	@bash -c read -n 1 -s
	@python tools/extractfv.py ./images/abl.img ./ABL_original.efi
	@fastboot boot ./ABL_original.efi
	@echo 'If the exploit existed in the new abl image, the device will show two lines of "Press Volume Down key to enter Fastboot mode, waiting for 5 seconds into Normal mode..."'
	@echo 'If the exploit does not exist in the new abl image, the device will show red state screen'
	@rm ./ABL_original.efi

test:
	bash ./tests/runall.sh
