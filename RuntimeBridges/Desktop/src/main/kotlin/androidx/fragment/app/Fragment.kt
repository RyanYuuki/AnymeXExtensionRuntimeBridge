package androidx.fragment.app

import android.app.Activity
import android.content.Context
import android.content.res.Resources
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup

open class Fragment {
    var arguments: Bundle? = null
    var tag: String? = null
    val childFragmentManager: FragmentManager = FragmentManager()
    var parentFragmentManager: FragmentManager = FragmentManager()

    open fun getContext(): Context? = null
    open fun requireContext(): Context = getContext() ?: Context()
    open fun getActivity(): FragmentActivity? = null
    open fun requireActivity(): FragmentActivity = getActivity() ?: FragmentActivity()
    open fun getResources(): Resources = requireContext().getResources()
    open fun getString(id: Int): String = getResources().getString(id)
    open fun getString(id: Int, vararg formatArgs: Any?): String = getResources().getString(id, *formatArgs)
    open fun requireArguments(): Bundle = arguments ?: Bundle()
    open fun getLayoutInflater(): LayoutInflater? = null
    open fun getView(): View? = null
    open fun requireView(): View = getView() ?: View()
    open fun isAdded(): Boolean = true
    open fun isVisible(): Boolean = false
    open fun isDetached(): Boolean = false
    open fun onCreate(savedInstanceState: Bundle?) {}
    open fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View? = null
    open fun onViewCreated(view: View, savedInstanceState: Bundle?) {}
    open fun onStart() {}
    open fun onResume() {}
    open fun onPause() {}
    open fun onStop() {}
    open fun onDestroyView() {}
    open fun onDestroy() {}
    open fun onDetach() {}
}
