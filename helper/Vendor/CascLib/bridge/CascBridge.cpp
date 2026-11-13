#include "../include/CascBridge.h"
#include "../src/CascLib.h"

#include <cstdlib>

struct CascBridgeStorage {
    HANDLE handle;
};

CascBridgeStorage *casc_bridge_open(const char *path, int *error) {
    HANDLE handle = nullptr;
    if (!CascOpenStorage(path, 0, &handle)) {
        if (error) *error = (int)GetCascError();
        return nullptr;
    }
    if (error) *error = 0;
    return new CascBridgeStorage{handle};
}

int casc_bridge_read(CascBridgeStorage *storage, uint32_t file_data_id, uint8_t **data, size_t *size) {
    if (!storage || !data || !size) return ERROR_INVALID_PARAMETER;
    *data = nullptr;
    *size = 0;

    HANDLE file = nullptr;
    if (!CascOpenFile(storage->handle, CASC_FILE_DATA_ID(file_data_id), 0, CASC_OPEN_BY_FILEID, &file)) {
        return (int)GetCascError();
    }
    ULONGLONG length = 0;
    if (!CascGetFileSize64(file, &length) || length == 0 || length > 64 * 1024 * 1024) {
        int err = (int)GetCascError();
        CascCloseFile(file);
        return err ? err : ERROR_FILE_CORRUPT;
    }
    uint8_t *buffer = (uint8_t *)malloc((size_t)length);
    if (!buffer) {
        CascCloseFile(file);
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    DWORD read = 0;
    bool ok = CascReadFile(file, buffer, (DWORD)length, &read) && read == length;
    int err = ok ? 0 : (int)GetCascError();
    CascCloseFile(file);
    if (!ok) {
        free(buffer);
        return err ? err : ERROR_FILE_CORRUPT;
    }
    *data = buffer;
    *size = (size_t)length;
    return 0;
}

void casc_bridge_free(uint8_t *data) { free(data); }

void casc_bridge_close(CascBridgeStorage *storage) {
    if (!storage) return;
    CascCloseStorage(storage->handle);
    delete storage;
}
