# Camera: Device-specific configuration files.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.camera.xml:vendor/etc/permissions/android.hardware.camera.xml \
    $(LOCAL_PATH)/{{_extra_dir}}/ivi_camera_config.xml:vendor/etc/ivi_camera_config.xml

# External camera service

PRODUCT_PACKAGES += android.iacamera.provider@2.4-ivi-service \
                    android.ia.hardware.camera.provider@2.4-ivi \
                    android.hardware.camera.provider@2.4-impl-ia

PRODUCT_PACKAGES += android.ia.hardware.camera.provider-ivi \
					android.iacamera.provider-ivi-service

PRODUCT_PACKAGES += Camera2
PRODUCT_PACKAGES += MultiCameraApp
