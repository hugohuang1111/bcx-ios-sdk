#ifndef __BCX_BRIDGE_LISTENER_H__
#define __BCX_BRIDGE_LISTENER_H__

//#import <string>
//#include <string>

namespace BCXBridgeIOS {
    class BCXBridgeListener {
    public:

        typedef void (*tBCXBridgeUnityCallback)(const char* /*method*/, const char* /*json*/);

        BCXBridgeListener();

        void setUnityCallback(tBCXBridgeUnityCallback callback);
        void notifyUnity(const char* method, const char* params);

    protected:
        tBCXBridgeUnityCallback _callback;
    };
}

#endif // __BCX_BRIDGE_LISTENER_H__


