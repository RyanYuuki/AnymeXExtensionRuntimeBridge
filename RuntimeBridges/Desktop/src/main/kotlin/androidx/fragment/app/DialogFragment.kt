package androidx.fragment.app

import android.app.Dialog
import android.content.DialogInterface
import android.os.Bundle

open class DialogFragment : Fragment(), DialogInterface.OnCancelListener, DialogInterface.OnDismissListener {
    companion object {
        const val STYLE_NORMAL = 0
        const val STYLE_NO_TITLE = 1
        const val STYLE_NO_FRAME = 2
        const val STYLE_NO_INPUT = 3
    }

    var isCancelable: Boolean = true
    private var dialog: Dialog? = null

    open fun show(manager: FragmentManager, tag: String?) {
        this.tag = tag
        this.parentFragmentManager = manager
    }

    open fun show(manager: Any?, tag: String?) {
        this.tag = tag
    }

    open fun showNow(manager: FragmentManager, tag: String?) {
        this.tag = tag
        this.parentFragmentManager = manager
    }

    open fun dismiss() {}

    open fun dismissAllowingStateLoss() {}

    open fun dismissNow() {}

    open fun getDialog(): Dialog? = dialog

    open fun requireDialog(): Dialog = dialog ?: Dialog(requireContext())

    open fun onCreateDialog(savedInstanceState: Bundle?): Dialog = Dialog(requireContext())

    open fun setStyle(style: Int, theme: Int) {}

    override fun onCancel(dialog: DialogInterface) {}

    override fun onDismiss(dialog: DialogInterface) {}
}
