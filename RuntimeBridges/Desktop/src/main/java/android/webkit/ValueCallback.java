package android.webkit;

/**
 * A callback interface used to provide values asynchronously.
 */
public interface ValueCallback<T> {
    /**
     * Invoked when the value is available.
     * @param value The value.
     */
    void onReceiveValue(T value);
}
