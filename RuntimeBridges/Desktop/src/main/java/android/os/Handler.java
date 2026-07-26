package android.os;

public class Handler {
    public Handler(Looper looper) {
    }

    public boolean post(Runnable r) {
        if (r != null) {
            r.run();
        }
        return true;
    }
}
